#!/usr/bin/env python3

import argparse
import json
import os
import random
import sys
import time
from collections import Counter, defaultdict
from typing import Dict, List, Tuple, Union, Any

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader
from lemmatizer.model import Seq2SeqLemmatizer, Attention

PAD, UNK, BOS, EOS = "<pad>", "<unk>", "<bos>", "<eos>"
MAX_LEMMA_LEN = 40

def read_form_upos_lemma(path: str) -> List[Tuple[str, str, str]]:
    """
    Read conll-format training files and parse to triplets of form, upos, lemma

    Filtering Rules:
    1. Ignores lines that are empty or start with '#'.
    2. Ignores lines with fewer than 8 tab-separated columns.
    3. Ignores multi-word tokens (IDs containing '-' or '.').
    4. Ignores entries where the form or lemma is empty, or where the lemma 
       is an underscore ('_')

    Args:
        path (str): The file system path to the CoNLL-formatted input file.

    Returns:
        List[Tuple[str, str, str]]: A list of triplets, where each triplet 
            contains (form, upos, lemma).
            - form: the form of the word as it appears in the text
            - upos:  UPOS tag
            - lemma: the lemma

    Raises:
        FileNotFoundError: If the file at the specified path does not exist.
        OSError: If the file cannot be read due to system-level errors.
    """
    triples = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            
            # Skip empty lines and comments
            if not line.strip() or line.startswith("#"):
                continue
            
            cols = line.split("\t")
            if len(cols) < 8:
                continue
            
            # Skip multi-word tokens (e.g., 1-2 or 1.1)
            tok_id = cols[0]
            if "-" in tok_id or "." in tok_id:
                continue
            
            # CoNLL format: Col 1 = Form, Col 2 = Lemma, Col 3 = UPOS
            form, lemma, upos = cols[1], cols[2], cols[3]
            
            # Only keep entries with valid, non-empty lemmas
            if form and lemma and lemma != "_":
                triples.append((form, upos, lemma))
                
    return triples

# ---------------------------------------------------------------------------
# Frequency dictionary 
# ---------------------------------------------------------------------------

def build_lemma_dict(
    triples: List[Tuple[str, str, str]], 
    min_purity: float = 0.7
) -> Tuple[Dict[str, str], Dict[str, Counter], List[str], List[str]]:
    """Creates a high-confidence lookup table for form-UPOS to lemma mappings.

    This function aggregates all lemmas associated with a specific "lowercase_form|UPOS" 
    pair. If a single lemma is dominant enough (appearing at least `min_purity` percent 
    of the time), it is added to a lookup dictionary. 

    Genuinely ambiguous pairs (where no single lemma meets the purity threshold) 
    are intentionally omitted. This ensures that the lookup table only contains 
    high-confidence mappings, while ambiguous cases are deferred to the neural 
    model for more nuanced prediction.

    Args:
        triples (List[Tuple[str, str, str]]): A list of triplets in the format 
            (form, upos, lemma).
        min_purity (float): The minimum ratio (0.0 to 1.0) of the most frequent 
            lemma relative to the total occurrences required to consider the 
            mapping "dominant". Defaults to 0.7.

    Returns:
        Tuple[Dict[str, str], Dict[str, Counter], List[str], List[str]]: A tuple 
            containing four elements:
            - lemma_dict (Dict[str, str]): The final lookup table mapping 
                "form|UPOS" strings to their dominant lemma.
            - counts (Dict[str, Counter]): The raw frequency distribution of 
                lemmas for every encountered "form|UPOS" pair.
            - keeplist (List[str]): A list of "form|UPOS" keys that met the 
                purity threshold.
            - droplist (List[str]): A list of "form|UPOS" keys that were too 
                ambiguous and were excluded from the lookup table.
    """
    # counts: Maps "form|UPOS" -> Counter({lemma1: count, lemma2: count, ...})
    counts: Dict[str, Counter] = defaultdict(Counter)
    for form, upos, lemma in triples:
        key = f"{form.lower()}|{upos}"
        counts[key][lemma] += 1

    lemma_dict = {}
    keeplist = []
    droplist = []
    
    for key, counter in counts.items():
        total = sum(counter.values())
        # Extract the most common lemma and its frequency
        lemma, freq = counter.most_common(1)[0]
        
        if freq / total >= min_purity:
            lemma_dict[key] = lemma
            keeplist.append(key)
        else:    
            droplist.append(key)
            
    return lemma_dict, counts, keeplist, droplist


def dict_lookup(form: str, upos: str, lemma_dict: Dict[str, str]) -> str:
    ''''Helper function to actually do the dict lookups'''
    return lemma_dict.get(f"{form.lower()}|{upos}")

# ---------------------------------------------------------------------------
# Vocabularies
# ---------------------------------------------------------------------------

class Vocab:
    """A bidirectional mapping between tokens (strings) and their integer IDs.

    This class provides a simple interface for encoding strings into indices 
    for model input and decoding indices back into human-readable strings.

    Attributes:
        itos (List[str]): Index-to-string mapping. The index in the list 
            represents the ID, and the value is the token.
        stoi (Dict[str, int]): String-to-index mapping for efficient lookups.
    """

    def __init__(self, itos: List[str]):
        """Initializes the Vocab object with a list of tokens.

        Args:
            itos (List[str]): A list of all unique tokens in the vocabulary, 
                ordered by their intended ID.
        """
        self.itos = itos
        self.stoi = {s: i for i, s in enumerate(itos)}

    def __len__(self) -> int:
        """Get the total number of tokens in the vocabulary.

        Returns:
            int: The size of the vocabulary.
        """
        return len(self.itos)

    def encode(self, s: str) -> int:
        """Converts a token string into its corresponding integer ID.

        If the token is not found in the vocabulary, it returns the ID of the 
        global `UNK` token.

        Args:
            s (str): The token string to encode.

        Returns:
            int: The integer ID of the token, or the ID of `UNK` if not found.
        """
        # Note: UNK is assumed to be a globally defined token string
        return self.stoi.get(s, self.stoi[UNK])

    def decode(self, i: int) -> str:
        """Converts an integer ID back into its corresponding token string.

        If the index is out of the bounds of the vocabulary, it returns 
        the global `UNK` token.

        Args:
            i (int): The integer ID to decode.

        Returns:
            str: The token string, or `UNK` if the index is invalid.
        """
        # Note: UNK is assumed to be a globally defined token string
        return self.itos[i] if 0 <= i < len(self.itos) else UNK

def build_char_vocab(triples: List[Tuple[str, str, str]]) -> Vocab:
    """
    Create a character-level vocabulary from the training triplets.

    Iterate through all forms and lemmas in the dataset to 
    collect every unique character present. The vocabulary is constructed by 
    combining a set of predefined special tokens with the sorted list of 
    discovered characters.

    Special tokens added to the start of the vocabulary:
    - PAD: Padding token for batching.
    - UNK: Unknown token for characters not seen during training.
    - BOS: Beginning-of-sentence token for decoder initialization.
    - EOS: End-of-sentence token to signal the end of a lemma.

    Args:
        triples (List[Tuple[str, str, str]]): A list of triplets in the format 
            (form, upos, lemma).

    Returns:
        Vocab: A Vocab instance containing the mapping for characters, 
            including special tokens and sorted unique characters.
    """
    chars = Counter()
    for form, _, lemma in triples:
        # Convert to lowercase to ensure the vocabulary is case-insensitive
        chars.update(list(form.lower()))
        chars.update(list(lemma.lower()))
        
    # Special tokens are placed first to ensure they have consistent, low-index IDs
    itos = [PAD, UNK, BOS, EOS] + sorted(chars.keys())
    return Vocab(itos)


def build_upos_vocab(triples: List[Tuple[str, str, str]]) -> Vocab:
    """
    Create a vocabulary for UPOS tags.

    This function extracts all unique UPOS tags from the training triplets 
    and sorts them to ensure deterministic ID assignment.

    Special tokens added to the start of the vocabulary:
    - PAD: Padding token for batching.
    - UNK: Unknown token for tags not seen during training.

    Args:
        triples (List[Tuple[str, str, str]]): A list of triplets in the format 
            (form, upos, lemma).

    Returns:
        Vocab: A Vocab instance containing the mapping for UPOS tags, 
            including special tokens and sorted unique tags.
    """
    # Extract unique UPOS tags using a set comprehension
    tags = sorted({upos for _, upos, _ in triples})
    
    # Special tokens are placed first
    return Vocab([PAD, UNK] + tags)

# ---------------------------------------------------------------------------
#  Dataset -- only the (form, upos, lemma) triples the dictionary can't
#    already resolve confidently go through the neural model for inference.
#    For training the neural model ALL pairs are used so it learns
#    general spelling patterns robustly.
# ---------------------------------------------------------------------------

class LemmaDataset(Dataset):
    """A PyTorch Dataset for the lemmatization task.
    This class handles the conversion of raw (form, upos, lemma) triplets into 
    integer-encoded sequences suitable for a Sequence-to-Sequence model. 
    """

    def __init__(self, data: Dict[str, Any], split: str = 'train'):
        """Initializes the LemmaDataset using a data dictionary.

        Args:
            data (Dict[str, Any]): The dictionary returned by prepare_data, 
                containing 'train_triples', 'dev_triples', 'char_vocab', etc.
            split (str): Either 'train' or 'dev' to determine which 
                triples to use. Defaults to 'train'.

        Raises:
            ValueError: If the split argument is not 'train' or 'dev'.
        """
        # 1. Extract Vocabularies (used in both train and dev)
        self.cv = data['char_vocab']
        self.uv = data['upos_vocab']

        # 2. Determine which triples to use
        if split == 'train':
            self.triples = data['train_triples']
        elif split == 'dev':
            self.triples = data['dev_triples']
        else:
            # Protest vociferously
            raise ValueError(
                f"INVALID SPLIT: '{split}' is not a valid split! "
                f"You must choose either 'train' or 'dev'. "
                f"Check your arguments in main()."
            )

    def __len__(self) -> int:
        """Returns the total number of samples in the dataset.

        Returns:
            int: The number of triplets.
        """
        return len(self.triples)

    def __getitem__(self, idx: int) -> Dict[str, Union[List[int], int]]:
        """Fetches and encodes a single training sample.

        This method performs lowercase normalization and converts strings into 
        integer sequences using the provided vocabularies.

        The target sequences are prepared for teacher forcing:
        - `tgt_in`: The sequence the decoder sees. It starts with the 
          Beginning-of-Sentence (BOS) token and contains the lemma.
        - `tgt_out`: The sequence the decoder is trying to predict. It 
          contains the lemma and ends with the End-of-Sentence (EOS) token.

        Args:
            idx (int): The index of the sample to retrieve.

        Returns:
            Dict[str, Union[List[int], int]]: A dictionary containing:
                - "src" (List[int]): Encoded character IDs of the surface form.
                - "tgt_in" (List[int]): Encoded IDs of [BOS] + lemma.
                - "tgt_out" (List[int]): Encoded IDs of lemma + [EOS].
                - "upos" (int): The encoded integer ID of the UPOS tag.
        """
        form, upos, lemma = self.triples[idx]
        
        # Source: encoded characters of the surface form (lowercased)
        src = [self.cv.encode(c) for c in form.lower()]
        
        # Target Input: [BOS] followed by the encoded lemma (lowercased)
        tgt_in = [self.cv.stoi[BOS]] + [self.cv.encode(c) for c in lemma.lower()]
        
        # Target Output: Encoded lemma (lowercased) followed by [EOS]
        tgt_out = [self.cv.encode(c) for c in lemma.lower()] + [self.cv.stoi[EOS]]
        
        return {
            "src": src, 
            "tgt_in": tgt_in, 
            "tgt_out": tgt_out,
            "upos": self.uv.encode(upos),
        }

def collate(batch: List[Dict[str, Any]], pad_id: int) -> Dict[str, torch.Tensor]:
    """Pads a batch of variable-length samples into fixed-size tensors.

    This function is designed to be used as a `collate_fn` for a PyTorch DataLoader. 
    It takes a list of samples from the `LemmaDataset` and pads the sequences 
    (`src`, `tgt_in`, `tgt_out`) to the length of the longest sequence in the 
    current batch.

    Note on Loss Calculation:
        The `tgt_out` tensor is initialized with -100. In PyTorch, `nn.CrossEntropyLoss` 
        defaults to ignoring the index -100, ensuring that padding tokens do not 
        contribute to the gradient or the final loss.

    Args:
        batch (List[Dict[str, Any]]): A list of samples, where each sample is a 
            dictionary containing "src", "tgt_in", "tgt_out", and "upos".
        pad_id (int): The integer ID used for padding sequences.

    Returns:
        Dict[str, torch.Tensor]: A dictionary of padded tensors:
            - "src" (torch.Tensor): Padded source character IDs. 
                Shape: (batch_size, max_src_len), Dtype: torch.long.
            - "src_len" (torch.Tensor): Actual lengths of the source sequences 
                before padding. Shape: (batch_size,), Dtype: torch.long.
            - "tgt_in" (torch.Tensor): Padded decoder input IDs. 
                Shape: (batch_size, max_tgt_len), Dtype: torch.long.
            - "tgt_out" (torch.Tensor): Padded target output IDs (with -100 for padding). 
                Shape: (batch_size, max_tgt_len), Dtype: torch.long.
            - "upos" (torch.Tensor): Batch of UPOS tag IDs. 
                Shape: (batch_size,), Dtype: torch.long.
    """
    B = len(batch)
    # Determine maximum lengths in this specific batch for dynamic padding
    max_src = max(len(x["src"]) for x in batch)
    max_tgt = max(len(x["tgt_in"]) for x in batch)

    # Pre-allocate tensors filled with padding values
    src = torch.full((B, max_src), pad_id, dtype=torch.long)
    src_len = torch.zeros(B, dtype=torch.long)
    tgt_in = torch.full((B, max_tgt), pad_id, dtype=torch.long)
    
    # Initialize target output with -100 so padding is ignored by CrossEntropyLoss
    tgt_out = torch.full((B, max_tgt), -100, dtype=torch.long)
    upos = torch.zeros(B, dtype=torch.long)

    for b, ex in enumerate(batch):
        s, ti, to = ex["src"], ex["tgt_in"], ex["tgt_out"]
        
        # Fill the pre-allocated tensors using slicing
        src[b, :len(s)] = torch.tensor(s, dtype=torch.long)
        src_len[b] = len(s)
        tgt_in[b, :len(ti)] = torch.tensor(ti, dtype=torch.long)
        tgt_out[b, :len(to)] = torch.tensor(to, dtype=torch.long)
        upos[b] = ex["upos"]

    return {
        "src": src, 
        "src_len": src_len, 
        "tgt_in": tgt_in, 
        "tgt_out": tgt_out, 
        "upos": upos
    }

# ---------------------------------------------------------------------------
# Training / evaluation
# ---------------------------------------------------------------------------

def get_device():
    """
    Get the device that will be used for training : 
    MPS for Apple Silicon, CUDA for CUDA compatible devices
    Otherwise, defaults to cpu
    """
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


@torch.no_grad()
def evaluate(
    model: torch.nn.Module, 
    loader: DataLoader, 
    device: torch.device, 
    char_vocab: Any, 
    dev_triples: List[Tuple[str, str, str]], 
    lemma_dict: Dict[Tuple[str, str], str]
) -> Tuple[float, float]:
    """Evaluates the model using both neural-only and hybrid lookup strategies.

    This function calculates two accuracy metrics. The neural-only accuracy 
    measures the raw performance of the seq2seq model. The hybrid accuracy 
    measures performance when a dictionary lookup is attempted first, falling 
    back to the neural model only if the dictionary lookup fails.

    Args:
        model: The neural sequence-to-sequence model to evaluate.
        loader: PyTorch DataLoader providing batches of input tensors.
        device: The device (CPU/GPU) to move tensors to.
        char_vocab: The character vocabulary object used for greedy decoding.
        dev_triples: A list of tuples where each tuple is (form, upos, gold_lemma).
        lemma_dict: A dictionary where keys are (form, upos) and values are 
            the correct lemmas, used for the hybrid fallback strategy.

    Returns:
        A tuple containing:
            - neural_acc (float): Accuracy of the pure neural model.
            - hybrid_acc (float): Accuracy of the dictionary-first hybrid model.
    """
    model.eval()
    neural_correct = 0
    hybrid_correct = 0
    total = 0
    idx = 0
    for batch in loader:
        # Move batch tensors to the specified device
        batch = {k: v.to(device) for k, v in batch.items()}

        # Generate predictions using the model's greedy decoding
        preds = model.greedy_decode(batch["src"], batch["src_len"], batch["upos"], char_vocab)
        for pred in preds:
            form, upos, gold_lemma = dev_triples[idx]
            idx += 1
            total += 1
            # 1. Neural-only evaluation
            if pred.lower() == gold_lemma.lower():
                neural_correct += 1
            
            # 2. Hybrid evaluation: Dictionary lookup -> Neural fallback
            dict_pred = dict_lookup(form, upos, lemma_dict)
            final_pred = dict_pred if dict_pred is not None else pred
            if final_pred.lower() == gold_lemma.lower():
                hybrid_correct += 1

    total = max(total, 1)
    return neural_correct / total, hybrid_correct / total

def log(message: str):
    """Centralized logger to keep print statements consistent."""
    print(f"[info] {message}")

def setup_environment(args):
    """Handles seeds, directories, and device selection."""
    random.seed(args.seed)
    torch.manual_seed(args.seed)
    os.makedirs(args.output, exist_ok=True)
    
    device = get_device()
    log(f"using device: {device}")
    return device

def save_artifacts(args, data):
    """Handles all file exports to the output directory."""
    #0 get items from data
    lemma_dict = data['lemma_dict']
    char_vocab = data["char_vocab"]
    upos_vocab = data["upos_vocab"]
    keeplist = data['keeplist']
    droplist = data['droplist']
    counts = data['counts']
    # 1. Standard exports (always happen)

    with open(os.path.join(args.output, "lemma_dict.json"), "w", encoding="utf-8") as f:
        json.dump(lemma_dict, f, ensure_ascii=False, indent=1)
    
    with open(os.path.join(args.output, "lemma_vocabs.json"), "w", encoding="utf-8") as f:
        json.dump({"char": char_vocab.itos, "upos": upos_vocab.itos}, f, ensure_ascii=False, indent=1)

    # 2. Conditional exports (only if export_only is True)
    if args.export_only:
        with open(os.path.join(args.output, "lemma_counts_dict.json"), "w", encoding="utf-8") as f:
            json.dump(counts, f, ensure_ascii=False, indent=1)
        with open(os.path.join(args.output, "lemma_keeplist.txt"), "w", encoding="utf-8") as d:
            d.write('\n'.join(keeplist) + '\n')
        with open(os.path.join(args.output, "lemma_droplist.txt"), "w", encoding="utf-8") as d:
            d.write('\n'.join(droplist) + '\n')
        
        log(f"Exports complete: 5 files dumped to {args.output}")

def prepare_data(args, device):
    """Loads data and builds the necessary dictionaries and vocabularies."""
    log("reading data ...")
    train_triples = read_form_upos_lemma(args.train)
    dev_triples = read_form_upos_lemma(args.dev)
    log(f"train pairs: {len(train_triples)}  dev pairs: {len(dev_triples)}")

    log("building frequency dictionary ...")
    lemma_dict, counts, keeplist, droplist = build_lemma_dict(
        train_triples, min_purity=args.min_dict_purity
    )
    log(f"dictionary covers {len(lemma_dict)} distinct (form,upos) pairs")

    char_vocab = build_char_vocab(train_triples)
    upos_vocab = build_upos_vocab(train_triples)
    log(f"chars={len(char_vocab)} upos_tags={len(upos_vocab)}")

    return {
        "train_triples": train_triples,
        "dev_triples": dev_triples,
        "lemma_dict": lemma_dict,
        "counts": counts,
        "keeplist": keeplist,
        "droplist": droplist,
        "char_vocab": char_vocab,
        "upos_vocab": upos_vocab
    }

def print_training_report(best_acc: float, ckpt_path: str, output_dir: str):
    """Prints a formatted summary of the training results and usage instructions."""
    
    report = f"""
{'='*60}
[DONE] Training Complete
{'='*60}
  Best hybrid (dict+neural) dev accuracy: {best_acc*100:.2f}%
  Checkpoint: {ckpt_path}
  Dictionary: {os.path.join(output_dir, 'lemma_dict.json')}
  Vocabs:     {os.path.join(output_dir, 'lemma_vocabs.json')}

  Behind the scenes:
  For each (form, predicted_upos), first check the dictionary ; 
  only run the seq2seq model's greedy_decode for pairs 
  the dictionary doesn't cover.
{'='*60}
"""
    print(report)

def main():
    ap = argparse.ArgumentParser(description="Train a char-seq2seq UD lemmatizer.")
    ap.add_argument("--train", required=True)
    ap.add_argument("--dev", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--export_only", action="store_true", default=False, help="Skip the actual training, just give me the dicts that would be used in training.")
    ap.add_argument("--epochs", type=int, default=50)
    ap.add_argument("--batch_size", type=int, default=128)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--enc_hidden", type=int, default=512)
    ap.add_argument("--dec_hidden", type=int, default=1024)
    ap.add_argument("--dropout", type=float, default=0.3)
    ap.add_argument("--min_dict_purity", type=float, default=0.7,
                     help="Only trust the frequency dictionary for a (form,upos) pair "
                          "if its majority lemma makes up at least this fraction of occurrences.")
    ap.add_argument("--patience", type=int, default=6)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    # 1. Setup
    device = setup_environment(args)
    if args.export_only:
        print(">>>>>>>>>>>>>>[info] Running in EXPORT ONLY MODE<<<<<<<<<<<<<<")

    # 2. Prepare data
    data = prepare_data(args, device)

    # 3. Exports
    save_artifacts(args, data) # Unpacks the dictionary into function arguments

    # 4. Early Exit
    if args.export_only:
        sys.exit(0)

    train_ds = LemmaDataset(data, split='train')
    dev_ds = LemmaDataset(data, split='dev')
    pad_id = data['char_vocab'].stoi[PAD]

    train_loader = DataLoader(train_ds, batch_size=args.batch_size, shuffle=True,
                               collate_fn=lambda b: collate(b, pad_id))
    dev_loader = DataLoader(dev_ds, batch_size=args.batch_size, shuffle=False,
                             collate_fn=lambda b: collate(b, pad_id))

    model = Seq2SeqLemmatizer(
        num_chars=len(data['char_vocab']), num_upos=len(data['upos_vocab']),
        enc_hidden=args.enc_hidden, dec_hidden=args.dec_hidden, dropout=args.dropout,
    ).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode="max", factor=0.5, patience=2)

    best_hybrid_acc = -1.0
    epochs_no_improve = 0
    ckpt_path = os.path.join(args.output, "best_lemmatizer.pt")

    #printing header, cols…
    # Define the widths as constants so they always match
    W = {'ep': 5, 'ls': 8, 'nr': 8, 'hy': 8, 'tm': 6}    
    # Use the ^ symbol to center the text within the defined width
    header = (
        f"{'Epoch':^{W['ep']}} | "
        f"{'Loss':^{W['ls']}} | "
        f"{'Neural%':^{W['nr']}} | "
        f"{'Hybrid%':^{W['hy']}} | "
        f"{'Time':^{W['tm']}}"
    )

    print(header)## print the header message
    print("-" * len(header)) # Adds a clean separator line
    

    # 5 run loop for n epochs
    for epoch in range(1, args.epochs + 1):
        starttime = time.time()    
        model.train()
        total_loss, n_batches = 0.0, 0
        for batch in train_loader:
            batch = {k: v.to(device) for k, v in batch.items()}
            optimizer.zero_grad()
            logits = model(batch["src"], batch["src_len"], batch["upos"], batch["tgt_in"])
            loss = F.cross_entropy(
                logits.reshape(-1, logits.size(-1)), batch["tgt_out"].reshape(-1),
                ignore_index=-100)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 5.0)
            optimizer.step()
            total_loss += loss.item()
            n_batches += 1

        neural_acc, hybrid_acc = evaluate(model, dev_loader, device, char_vocab, dev_triples, lemma_dict)
        scheduler.step(hybrid_acc)
        endtime = time.time()
        delta = endtime - starttime    
        avg_loss = total_loss / max(n_batches, 1)

        # 1. Format the metrics line for easy scanning
        # :03d -> 3 digits, padded with 0
        # :8.4f -> 8 total characters wide, 4 after decimal
        metrics = (
            f"{epoch:03d}   | " 
            f"{avg_loss:{W['ls']}.4f} | "
            f"{neural_acc*100:{W['nr']-1}.2f}% | " # Subtract 1 to make room for the % sign
            f"{hybrid_acc*100:{W['hy']-1}.2f}% | "
            f"{delta:{W['tm']-1}.0f}s"
        )

        if hybrid_acc > best_hybrid_acc:
            best_hybrid_acc = hybrid_acc
            epochs_no_improve = 0
            torch.save({"model_state": model.state_dict(), "args": vars(args)}, ckpt_path)
            # Log metrics and the event on separate lines or with a clear marker
            log(f"{metrics}  ⭐ New Best! (Saved)")

        else:
            log(metrics)
            epochs_no_improve += 1
            if epochs_no_improve >= args.patience:
            	log(f"Early stopping triggered: No improvement for {args.patience} epochs.")
            	break

    # when training complete:
    print_training_report(best_hybrid_acc, ckpt_path, args.output)


if __name__ == "__main__":
    main()
