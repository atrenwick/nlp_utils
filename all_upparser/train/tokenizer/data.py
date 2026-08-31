"""Data loading for the character-level tokenizer / sentence-segmenter.

We reconstruct raw text from CoNLL-U FORM + MISC(SpaceAfter=No) fields and
label every character with one of four classes:

    0  INSIDE     character is part of a token, but not its last character
    1  TOKEN_END  last character of a token; the sentence continues
    2  SENT_END   last character of a token; this is also the last token
                  of the sentence
    3  SPACE      whitespace between tokens (not part of any token)

This mirrors the tagging scheme used by UDPipe/Stanza's tokenizers. At
inference time, a model trained on these labels turns raw text into a
sequence of tokens and sentences without ever having seen whitespace-
delimited "words" as a hard assumption -- important for languages/scripts
where token boundaries don't align with whitespace.

Limitation: multiword tokens (e.g. French "du" -> "de"+"le") are handled by
using the multiword span's surface FORM for the raw-text reconstruction and
skipping the subsumed word rows for that purpose. This is correct for most
UD treebanks but can be imperfect for scripts with very heavy multiword-token
usage (e.g. Arabic, Hebrew) -- in those cases consider augmenting with a
dedicated word-segmentation head down the line.
"""
import torch
from torch.utils.data import Dataset

from common.conllu_io import is_empty_node, is_multiword_token, is_normal_token
from common.vocab import Vocab

LABEL_INSIDE = 0
LABEL_TOKEN_END = 1
LABEL_SENT_END = 2
LABEL_SPACE = 3
NUM_LABELS = 4


def _space_after(tok):
    return tok["misc"].get("SpaceAfter") != "No"


def sentences_to_char_stream(sentences):
    """Turn a list of raw CoNLL-U sentences into one long (chars, labels) stream."""
    chars, labels = [], []
    for sent in sentences:
        skip_ids = set()
        for tok in sent:
            if is_multiword_token(tok):
                start, end = tok["id"].split("-")
                for i in range(int(start), int(end) + 1):
                    skip_ids.add(str(i))

        surface_rows = [
            t for t in sent
            if not is_empty_node(t) and not (is_normal_token(t) and t["id"] in skip_ids)
        ]
        word_rows = [t for t in sent if is_normal_token(t)]
        last_word_id = word_rows[-1]["id"] if word_rows else None

        for row in surface_rows:
            form = row["form"]
            if not form:
                continue
            for ci, ch in enumerate(form):
                chars.append(ch)
                if ci < len(form) - 1:
                    labels.append(LABEL_INSIDE)
                    continue
                if is_multiword_token(row):
                    end_id = row["id"].split("-")[1]
                    is_last = end_id == last_word_id
                else:
                    is_last = row["id"] == last_word_id
                labels.append(LABEL_SENT_END if is_last else LABEL_TOKEN_END)
            if _space_after(row):
                chars.append(" ")
                labels.append(LABEL_SPACE)
    return chars, labels


def build_char_vocab(chars):
    v = Vocab()
    v.build_from_tokens(chars)
    return v


def chunk_stream(chars, labels, seq_len):
    """Split the character stream into non-overlapping fixed-length windows.

    Note: a token that straddles a window boundary will be split across two
    training examples. This is a simplification; for higher accuracy switch
    to overlapping windows with stride = seq_len // 2 and only supervise the
    central portion of each window.
    """
    examples = []
    for start in range(0, len(chars), seq_len):
        c = chars[start:start + seq_len]
        l = labels[start:start + seq_len]
        if c:
            examples.append((c, l))
    return examples


class TokenizerDataset(Dataset):
    def __init__(self, examples, char_vocab):
        self.examples = examples
        self.char_vocab = char_vocab

    def __len__(self):
        return len(self.examples)

    def __getitem__(self, idx):
        chars, labels = self.examples[idx]
        ids = torch.tensor([self.char_vocab.encode(c) for c in chars], dtype=torch.long)
        lab = torch.tensor(labels, dtype=torch.long)
        return ids, lab


def collate_fn(batch, pad_id):
    lengths = [len(ids) for ids, _ in batch]
    max_len = max(lengths)
    padded_ids = torch.full((len(batch), max_len), pad_id, dtype=torch.long)
    padded_labels = torch.full((len(batch), max_len), -100, dtype=torch.long)
    for i, (ids, lab) in enumerate(batch):
        padded_ids[i, :len(ids)] = ids
        padded_labels[i, :len(lab)] = lab
    return padded_ids, padded_labels, torch.tensor(lengths, dtype=torch.long)
