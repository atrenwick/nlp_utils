"""Data loading, vocab building and lemma edit-scripts for the joint
POS-tagging / morphological-features / lemmatization / dependency-parsing
model.

Design notes
------------
* FEATS is treated as a single categorical label (the whole pipe-separated
  string, e.g. "Case=Nom|Gender=Masc|Number=Sing") rather than decomposed
  into independent per-feature classifiers. This is the approach UDPipe 2.0
  uses: in practice the number of distinct feature *combinations* observed
  per language is manageable, and it keeps the model (and the eventual
  Core ML graph) simple. If you need robustness to unseen feature
  combinations, swap FeatsHead for a multi-label sigmoid head instead.

* Lemmas are predicted as an "edit script" class rather than generated
  character-by-character. We compute the minimal transformation from the
  lowercased word FORM to the lowercased LEMMA (shared prefix / shared
  suffix / replacement middle), encode it as a string, and treat that
  string as a classification target. At inference time the same rule is
  deterministically re-applied to the input FORM. This avoids a seq2seq
  decoder, which is both slower to train and far more expensive to run and
  convert to Core ML.

* A synthetic ROOT token is prepended to every sentence at position 0. This
  lets `head == 0` (UD's convention for "attaches to the root") map
  directly onto tensor index 0, so head prediction is simply "pick one of
  the T tensor positions" with no off-by-one bookkeeping.
"""
import torch
from torch.utils.data import Dataset

from common.conllu_io import normal_tokens, read_conllu_sentences
from common.vocab import Vocab

ROOT_TOKEN = "<root>"
ROOT_CHAR = "<root>"
IGNORE_INDEX = -100


# ---------------------------------------------------------------------------
# Lemma edit-scripts
# ---------------------------------------------------------------------------

def _common_prefix_len(a, b):
    n = 0
    while n < len(a) and n < len(b) and a[n] == b[n]:
        n += 1
    return n


def _common_suffix_len(a, b, max_len):
    n = 0
    while n < max_len and n < len(a) and n < len(b) and a[-(n + 1)] == b[-(n + 1)]:
        n += 1
    return n


def compute_lemma_rule(form, lemma):
    """Encode the transformation form -> lemma as a compact rule string.

    Casing is normalised away (rule operates on lowercased strings) and
    reapplied heuristically at inference time (see `apply_lemma_rule`).
    """
    f, l = form.lower(), lemma.lower()
    if f == l:
        return "IDENTITY"
    p = _common_prefix_len(f, l)
    s = _common_suffix_len(f, l, max_len=min(len(f), len(l)) - p)
    middle = l[p:len(l) - s] if s > 0 else l[p:]
    return f"{p}|{s}|{middle}"


def apply_lemma_rule(form, rule):
    """Deterministically reconstruct a lemma from a form and a rule string."""
    if rule == "IDENTITY":
        result = form.lower()
    else:
        try:
            p_str, s_str, middle = rule.split("|", 2)
            p, s = int(p_str), int(s_str)
        except (ValueError, IndexError):
            return form
        f = form.lower()
        if p + s > len(f):
            return form
        prefix = f[:p]
        suffix = f[len(f) - s:] if s > 0 else ""
        result = prefix + middle + suffix
    if form[:1].isupper():
        result = result[:1].upper() + result[1:]
    return result


# ---------------------------------------------------------------------------
# Vocabularies
# ---------------------------------------------------------------------------

class Vocabs:
    def __init__(self):
        self.word = Vocab(specials=[ROOT_TOKEN])
        self.char = Vocab(specials=[ROOT_CHAR])
        self.upos = Vocab(specials=[ROOT_TOKEN])
        self.xpos = Vocab(specials=[ROOT_TOKEN])
        self.feats = Vocab(specials=[ROOT_TOKEN])
        self.deprel = Vocab()
        self.lemma_rule = Vocab()

    def build(self, sentences, min_word_freq=2, min_char_freq=1):
        from collections import Counter
        words, chars, upos, xpos, feats, deprel, rules = (
            Counter(), Counter(), Counter(), Counter(), Counter(), Counter(), Counter()
        )
        for sent in sentences:
            for tok in normal_tokens(sent):
                form = tok["form"]
                words[form.lower()] += 1
                for ch in form:
                    chars[ch] += 1
                upos[tok["upos"]] += 1
                xpos[tok["xpos"]] += 1
                feats[tok["feats"] if tok["feats"] else "_"] += 1
                if tok["deprel"] and tok["deprel"] != "_":
                    deprel[tok["deprel"]] += 1
                rules[compute_lemma_rule(form, tok["lemma"])] += 1

        self.word.build_from_counter(words, min_freq=min_word_freq)
        self.char.build_from_counter(chars, min_freq=min_char_freq)
        self.upos.build_from_counter(upos)
        self.xpos.build_from_counter(xpos)
        self.feats.build_from_counter(feats)
        self.deprel.build_from_counter(deprel)
        self.lemma_rule.build_from_counter(rules)

    def save(self, output_dir):
        import os
        self.word.save(os.path.join(output_dir, "word_vocab.json"))
        self.char.save(os.path.join(output_dir, "char_vocab.json"))
        self.upos.save(os.path.join(output_dir, "upos_vocab.json"))
        self.xpos.save(os.path.join(output_dir, "xpos_vocab.json"))
        self.feats.save(os.path.join(output_dir, "feats_vocab.json"))
        self.deprel.save(os.path.join(output_dir, "deprel_vocab.json"))
        self.lemma_rule.save(os.path.join(output_dir, "lemma_rule_vocab.json"))

    @classmethod
    def load(cls, output_dir):
        import os
        v = cls()
        v.word = Vocab.load(os.path.join(output_dir, "word_vocab.json"))
        v.char = Vocab.load(os.path.join(output_dir, "char_vocab.json"))
        v.upos = Vocab.load(os.path.join(output_dir, "upos_vocab.json"))
        v.xpos = Vocab.load(os.path.join(output_dir, "xpos_vocab.json"))
        v.feats = Vocab.load(os.path.join(output_dir, "feats_vocab.json"))
        v.deprel = Vocab.load(os.path.join(output_dir, "deprel_vocab.json"))
        v.lemma_rule = Vocab.load(os.path.join(output_dir, "lemma_rule_vocab.json"))
        return v


# ---------------------------------------------------------------------------
# Dataset
# ---------------------------------------------------------------------------

class UDSentence:
    __slots__ = ("word_ids", "char_ids", "upos_ids", "xpos_ids", "feats_ids",
                 "lemma_rule_ids", "heads", "deprel_ids")


def encode_sentence(sent, vocabs, max_word_len=20):
    words = normal_tokens(sent)

    word_ids = [vocabs.word.encode(ROOT_TOKEN)]
    char_ids = [[vocabs.char.encode(ROOT_CHAR)]]
    upos_ids = [IGNORE_INDEX]
    xpos_ids = [IGNORE_INDEX]
    feats_ids = [IGNORE_INDEX]
    lemma_rule_ids = [IGNORE_INDEX]
    heads = [IGNORE_INDEX]
    deprel_ids = [IGNORE_INDEX]

    for tok in words:
        form = tok["form"]
        word_ids.append(vocabs.word.encode(form.lower()))
        char_ids.append([vocabs.char.encode(c) for c in form[:max_word_len]] or
                         [vocabs.char.unk_id])
        upos_ids.append(vocabs.upos.encode(tok["upos"]))
        xpos_ids.append(vocabs.xpos.encode(tok["xpos"]))
        feats_ids.append(vocabs.feats.encode(tok["feats"] if tok["feats"] else "_"))
        lemma_rule_ids.append(vocabs.lemma_rule.encode(compute_lemma_rule(form, tok["lemma"])))
        try:
            head = int(tok["head"])
        except (ValueError, TypeError):
            head = 0
        heads.append(head)
        deprel_ids.append(vocabs.deprel.encode(tok["deprel"]) if tok["deprel"] else IGNORE_INDEX)

    s = UDSentence()
    s.word_ids = word_ids
    s.char_ids = char_ids
    s.upos_ids = upos_ids
    s.xpos_ids = xpos_ids
    s.feats_ids = feats_ids
    s.lemma_rule_ids = lemma_rule_ids
    s.heads = heads
    s.deprel_ids = deprel_ids
    return s


class UDDataset(Dataset):
    def __init__(self, sentences, vocabs, max_word_len=20):
        self.examples = [encode_sentence(s, vocabs, max_word_len) for s in sentences
                          if normal_tokens(s)]

    def __len__(self):
        return len(self.examples)

    def __getitem__(self, idx):
        return self.examples[idx]


def collate_fn(batch, word_pad_id, char_pad_id):
    batch_size = len(batch)
    seq_lengths = [len(ex.word_ids) for ex in batch]
    max_seq_len = max(seq_lengths)
    max_word_len = max(len(w) for ex in batch for w in ex.char_ids)
    max_word_len = max(max_word_len, 1)

    word_ids = torch.full((batch_size, max_seq_len), word_pad_id, dtype=torch.long)
    char_ids = torch.full((batch_size, max_seq_len, max_word_len), char_pad_id, dtype=torch.long)
    upos_ids = torch.full((batch_size, max_seq_len), IGNORE_INDEX, dtype=torch.long)
    xpos_ids = torch.full((batch_size, max_seq_len), IGNORE_INDEX, dtype=torch.long)
    feats_ids = torch.full((batch_size, max_seq_len), IGNORE_INDEX, dtype=torch.long)
    lemma_rule_ids = torch.full((batch_size, max_seq_len), IGNORE_INDEX, dtype=torch.long)
    heads = torch.full((batch_size, max_seq_len), IGNORE_INDEX, dtype=torch.long)
    deprel_ids = torch.full((batch_size, max_seq_len), IGNORE_INDEX, dtype=torch.long)

    for i, ex in enumerate(batch):
        n = len(ex.word_ids)
        word_ids[i, :n] = torch.tensor(ex.word_ids, dtype=torch.long)
        upos_ids[i, :n] = torch.tensor(ex.upos_ids, dtype=torch.long)
        xpos_ids[i, :n] = torch.tensor(ex.xpos_ids, dtype=torch.long)
        feats_ids[i, :n] = torch.tensor(ex.feats_ids, dtype=torch.long)
        lemma_rule_ids[i, :n] = torch.tensor(ex.lemma_rule_ids, dtype=torch.long)
        heads[i, :n] = torch.tensor(ex.heads, dtype=torch.long)
        deprel_ids[i, :n] = torch.tensor(ex.deprel_ids, dtype=torch.long)
        for j, w in enumerate(ex.char_ids):
            char_ids[i, j, :len(w)] = torch.tensor(w, dtype=torch.long)

    lengths = torch.tensor(seq_lengths, dtype=torch.long)
    return {
        "word_ids": word_ids, "char_ids": char_ids, "lengths": lengths,
        "upos_ids": upos_ids, "xpos_ids": xpos_ids, "feats_ids": feats_ids,
        "lemma_rule_ids": lemma_rule_ids, "heads": heads, "deprel_ids": deprel_ids,
    }


def load_dataset(path, vocabs=None, build_vocabs=False, min_word_freq=2):
    sentences = read_conllu_sentences(path)
    if build_vocabs:
        vocabs = Vocabs()
        vocabs.build(sentences, min_word_freq=min_word_freq)
    assert vocabs is not None, "Must supply vocabs unless build_vocabs=True"
    return UDDataset(sentences, vocabs), vocabs
