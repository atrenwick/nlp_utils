"""Fine-tune DistilBERT on CoNLL-U treebanks for joint UPOS / XPOS / FEATS /
lemma-rule / dependency parsing, for later on-device use via Core ML.

Same heads, same label vocabularies, same six output tensors as the
BiLSTM model in model.py -- only the encoder changes. So the Swift-side
decoding (argmax + vocab lookup, apply_lemma_rule, Chu-Liu-Edmonds) stays
as it is. What changes on the Swift side is the *input*: it must supply
WordPiece subword ids plus the index of each word's first subword (see
"On-device inputs" below).

Usage (from the project root, venv active):

    pip install transformers

    python -m tagger_parser.train_bert \
        --train data/en_ewt-train.conllu data/en_gum-train.conllu \
        --dev data/en_ewt-dev.conllu \
        --output out/bert_tagger_parser \
        --base_model distilbert-base-multilingual-cased

Choosing --base_model:
    distilbert-base-multilingual-cased   many languages, ~135M params
    distilbert-base-cased                English only, ~65M params (roughly
                                         half the on-device size)

Tokens
------
Tokenisation is an INPUT, as with your current model: each CoNLL-U word
is tokenised separately into WordPiece subwords. The model does not learn
word segmentation. Position 0 is the synthetic ROOT word and is
represented by the [CLS] subword, so `head == 0` still means "attaches to
root" with no off-by-one bookkeeping.

How subwords become word vectors
--------------------------------
`word_index[b, i]` is the position of word i's FIRST subword in
`input_ids`. The model gathers those positions out of the encoder output,
giving one vector per word ([B, T, hidden]), and everything after that is
word-level exactly like model.py. The gather happens inside the model, so
the Core ML graph takes (input_ids, word_index) and nothing else.

On-device inputs (what Swift must reproduce)
--------------------------------------------
For each word, tokenise it on its own with the same WordPiece rules the
Python tokenizer uses (vocab.txt and the casing / accent settings in
tokenizer_config.json), then build:

    input_ids  = [CLS] + pieces(word_1) + pieces(word_2) + ... + [SEP]
    word_index = [0, start_of_word_1, start_of_word_2, ...]

A word that produces no pieces becomes a single [UNK]. This script writes
`tokenizer_golden.json` (words -> expected input_ids / word_index for 50
dev sentences) so you can check a Swift tokenizer against the Python one
before trusting any model output.

Optimisation notes
------------------
Encoder and heads get separate learning rates: the encoder is already
trained and wants a small rate; the heads start from random init and want
a much larger one. Linear warmup then decay, stepped per batch.
"""
import argparse
import json
import os
import random
import time

import torch
import torch.nn as nn
from torch.utils.data import DataLoader, Dataset
from transformers import AutoModel, AutoTokenizer, get_linear_schedule_with_warmup

from common.conllu_io import normal_tokens, read_conllu_sentences
from tagger_parser.data import IGNORE_INDEX, Vocabs, encode_sentence
from tagger_parser.model import Biaffine, _mlp
from tagger_parser.train import compute_losses, get_device

LABEL_VOCABS = ("upos", "xpos", "feats", "deprel", "lemma_rule")


# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------

def gather_words(hidden, word_index):
    """[B, S, H] subword states + [B, T] first-subword indices -> [B, T, H].

    Shared by BertUDModel.forward and the Core ML inference wrapper in
    convert_bert.py so the two can't drift apart.
    """
    idx = word_index.unsqueeze(-1).expand(-1, -1, hidden.shape[-1])
    return torch.gather(hidden, 1, idx)


class BertUDModel(nn.Module):
    def __init__(self, encoder, num_upos, num_xpos, num_feats, num_lemma_rules,
                 num_deprel, arc_mlp_dim=400, label_mlp_dim=100, dropout=0.2,
                 tag_feature_dim=50, use_upos_feature=True,
                 use_feats_feature=True, use_lemma_feature=True):
        super().__init__()
        self.encoder = encoder
        hidden = encoder.config.hidden_size
        self.dropout = nn.Dropout(dropout)

        self.upos_head = nn.Linear(hidden, num_upos)
        self.xpos_head = nn.Linear(hidden, num_xpos)
        self.feats_head = nn.Linear(hidden, num_feats)
        self.lemma_head = nn.Linear(hidden, num_lemma_rules)

        # Soft UPOS / FEATS / lemma-rule predictions feed the parser, as in
        # model.py (see its docstring for why softmax rather than argmax).
        self.use_upos_feature = use_upos_feature
        self.use_feats_feature = use_feats_feature
        self.use_lemma_feature = use_lemma_feature
        parser_input_dim = hidden
        if use_upos_feature:
            self.upos_feature_proj = nn.Linear(num_upos, tag_feature_dim)
            parser_input_dim += tag_feature_dim
        if use_feats_feature:
            self.feats_feature_proj = nn.Linear(num_feats, tag_feature_dim)
            parser_input_dim += tag_feature_dim
        if use_lemma_feature:
            self.lemma_feature_proj = nn.Linear(num_lemma_rules, tag_feature_dim)
            parser_input_dim += tag_feature_dim

        self.arc_dep_mlp = _mlp(parser_input_dim, arc_mlp_dim, dropout)
        self.arc_head_mlp = _mlp(parser_input_dim, arc_mlp_dim, dropout)
        self.arc_biaffine = Biaffine(arc_mlp_dim, arc_mlp_dim, out_dim=1,
                                      bias1=True, bias2=False)
        self.label_dep_mlp = _mlp(parser_input_dim, label_mlp_dim, dropout)
        self.label_head_mlp = _mlp(parser_input_dim, label_mlp_dim, dropout)
        self.label_biaffine = Biaffine(label_mlp_dim, label_mlp_dim,
                                        out_dim=num_deprel, bias1=True, bias2=True)

    def build_parser_input(self, words, upos_logits, feats_logits, lemma_logits):
        parser_input = words
        if self.use_upos_feature:
            feat = self.upos_feature_proj(torch.softmax(upos_logits, dim=-1))
            parser_input = torch.cat([parser_input, feat], dim=-1)
        if self.use_feats_feature:
            feat = self.feats_feature_proj(torch.softmax(feats_logits, dim=-1))
            parser_input = torch.cat([parser_input, feat], dim=-1)
        if self.use_lemma_feature:
            feat = self.lemma_feature_proj(torch.softmax(lemma_logits, dim=-1))
            parser_input = torch.cat([parser_input, feat], dim=-1)
        return parser_input

    def forward(self, input_ids, attention_mask, word_index, lengths):
        hidden = self.encoder(input_ids=input_ids,
                              attention_mask=attention_mask).last_hidden_state
        words = self.dropout(gather_words(hidden, word_index))   # [B, T, H]

        upos_logits = self.upos_head(words)
        xpos_logits = self.xpos_head(words)
        feats_logits = self.feats_head(words)
        lemma_logits = self.lemma_head(words)
        parser_input = self.build_parser_input(
            words, upos_logits, feats_logits, lemma_logits)

        arc_logits = self.arc_biaffine(self.arc_dep_mlp(parser_input),
                                        self.arc_head_mlp(parser_input))   # [B, T, T]
        label_logits = self.label_biaffine(self.label_dep_mlp(parser_input),
                                            self.label_head_mlp(parser_input))

        # Padded word slots all gather subword 0, so they would look
        # identical to ROOT as head candidates and steal probability mass
        # from it. Mask them out as head columns. (Not needed at inference:
        # a single unpadded sentence has no padding.)
        t = arc_logits.size(-1)
        word_mask = torch.arange(t, device=lengths.device)[None, :] < lengths[:, None]
        arc_logits = arc_logits.masked_fill(~word_mask.unsqueeze(1), -1e4)

        return {
            "upos": upos_logits, "xpos": xpos_logits, "feats": feats_logits,
            "lemma_rule": lemma_logits, "arc": arc_logits, "label": label_logits,
        }


# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

def encode_example(sent, tokenizer, vocabs, max_subwords):
    """One sentence -> dict of subword ids, word->subword index, and labels.

    Labels come from data.encode_sentence, so label ids (including lemma
    rules and the IGNORE_INDEX at the ROOT slot) are identical to what the
    BiLSTM pipeline produces.
    """
    words = normal_tokens(sent)
    if not words:
        return None
    forms = [t["form"] for t in words]
    pieces = tokenizer(forms, add_special_tokens=False)["input_ids"]

    input_ids = [tokenizer.cls_token_id]
    word_index = [0]                       # ROOT == [CLS]
    for piece in pieces:
        word_index.append(len(input_ids))
        input_ids.extend(piece or [tokenizer.unk_token_id])
    input_ids.append(tokenizer.sep_token_id)
    if len(input_ids) > max_subwords:
        return None

    ud = encode_sentence(sent, vocabs)
    return {
        "words": forms, "input_ids": input_ids, "word_index": word_index,
        "upos_ids": ud.upos_ids, "xpos_ids": ud.xpos_ids,
        "feats_ids": ud.feats_ids, "lemma_rule_ids": ud.lemma_rule_ids,
        "heads": ud.heads, "deprel_ids": ud.deprel_ids,
    }


class BertUDDataset(Dataset):
    def __init__(self, sentences, tokenizer, vocabs, max_subwords):
        encoded = [encode_example(s, tokenizer, vocabs, max_subwords) for s in sentences]
        self.examples = [e for e in encoded if e is not None]
        self.skipped = len(encoded) - len(self.examples)

    def __len__(self):
        return len(self.examples)

    def __getitem__(self, idx):
        return self.examples[idx]


def collate(batch, pad_id):
    b = len(batch)
    s = max(len(e["input_ids"]) for e in batch)
    t = max(len(e["word_index"]) for e in batch)

    input_ids = torch.full((b, s), pad_id, dtype=torch.long)
    attention_mask = torch.zeros((b, s), dtype=torch.long)
    word_index = torch.zeros((b, t), dtype=torch.long)
    lengths = torch.tensor([len(e["word_index"]) for e in batch], dtype=torch.long)
    labels = {k: torch.full((b, t), IGNORE_INDEX, dtype=torch.long)
              for k in ("upos_ids", "xpos_ids", "feats_ids",
                        "lemma_rule_ids", "heads", "deprel_ids")}

    for i, e in enumerate(batch):
        n_sub, n_words = len(e["input_ids"]), len(e["word_index"])
        input_ids[i, :n_sub] = torch.tensor(e["input_ids"])
        attention_mask[i, :n_sub] = 1
        word_index[i, :n_words] = torch.tensor(e["word_index"])
        for k, tensor in labels.items():
            tensor[i, :n_words] = torch.tensor(e[k])

    return {"input_ids": input_ids, "attention_mask": attention_mask,
            "word_index": word_index, "lengths": lengths, **labels}


# ---------------------------------------------------------------------------
# Evaluation
# ---------------------------------------------------------------------------

def _forward(model, batch):
    return model(batch["input_ids"], batch["attention_mask"],
                 batch["word_index"], batch["lengths"])


@torch.no_grad()
def evaluate(model, loader, device, criterion):
    model.eval()
    totals = {k: 0 for k in ("upos", "xpos", "feats", "lemma_rule", "uas", "las", "tokens")}
    loss_sum, n_batches = 0.0, 0

    for batch in loader:
        batch = {k: v.to(device) for k, v in batch.items()}
        outputs = _forward(model, batch)
        loss, _ = compute_losses(outputs, batch, criterion)
        loss_sum += loss.item()
        n_batches += 1

        mask = batch["upos_ids"] != IGNORE_INDEX
        totals["tokens"] += mask.sum().item()
        for key in ("upos", "xpos", "feats", "lemma_rule"):
            preds = outputs[key].argmax(-1)
            gold = batch[f"{key}_ids"]
            totals[key] += (preds[mask] == gold[mask]).sum().item()

        arc_logits = outputs["arc"].clone()
        b, t, _ = arc_logits.shape
        eye = torch.eye(t, device=device, dtype=torch.bool).unsqueeze(0).expand(b, -1, -1)
        arc_logits.masked_fill_(eye, float("-inf"))   # a word can't head itself
        head_preds = arc_logits.argmax(-1)
        gold_heads = batch["heads"]
        head_mask = gold_heads != IGNORE_INDEX
        totals["uas"] += (head_preds[head_mask] == gold_heads[head_mask]).sum().item()

        c = outputs["label"].size(1)
        idx = head_preds.clamp(min=0).view(b, 1, t, 1).expand(-1, c, -1, 1)
        selected = torch.gather(outputs["label"], dim=3, index=idx).squeeze(3).transpose(1, 2)
        label_preds = selected.argmax(-1)
        both = (head_preds == gold_heads) & (label_preds == batch["deprel_ids"])
        totals["las"] += both[head_mask].sum().item()

    model.train()
    n = max(totals["tokens"], 1)
    metrics = {k: totals[k] / n for k in ("upos", "xpos", "feats", "lemma_rule", "uas", "las")}
    metrics["loss"] = loss_sum / max(n_batches, 1)
    return metrics


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def read_all(paths):
    sentences = []
    for path in paths:
        sentences.extend(read_conllu_sentences(path))
    return sentences


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--train", nargs="+", required=True,
                     help="One or more training .conllu files (mixing treebanks "
                          "helps out-of-domain robustness)")
    ap.add_argument("--dev", nargs="+", required=True, help="Dev .conllu file(s)")
    ap.add_argument("--output", required=True)
    ap.add_argument("--base_model", default="distilbert-base-multilingual-cased")
    ap.add_argument("--batch_size", type=int, default=16)
    ap.add_argument("--epochs", type=int, default=50)
    ap.add_argument("--encoder_lr", type=float, default=5e-5)
    ap.add_argument("--head_lr", type=float, default=1e-3)
    ap.add_argument("--warmup_ratio", type=float, default=0.1)
    ap.add_argument("--max_subwords", type=int, default=256,
                     help="Sentences longer than this many subwords are skipped "
                          "in training; also the Core ML input bound")
    ap.add_argument("--arc_mlp_dim", type=int, default=400)
    ap.add_argument("--label_mlp_dim", type=int, default=100)
    ap.add_argument("--dropout", type=float, default=0.2)
    ap.add_argument("--patience", type=int, default=10)
    ap.add_argument("--seed", type=int, default=13)
    ap.add_argument("--tag_feature_dim", type=int, default=50)
    for name in ("upos", "feats", "lemma"):
        ap.add_argument(f"--use_{name}_feature", dest=f"use_{name}_feature",
                         action="store_true", default=True)
        ap.add_argument(f"--no_use_{name}_feature", dest=f"use_{name}_feature",
                         action="store_false")
    args = ap.parse_args()

    random.seed(args.seed)
    torch.manual_seed(args.seed)
    os.makedirs(args.output, exist_ok=True)
    device = get_device()
    print(f"Using device: {device}")

    tokenizer = AutoTokenizer.from_pretrained(args.base_model)
    train_sents, dev_sents = read_all(args.train), read_all(args.dev)

    vocabs = Vocabs()
    vocabs.build(train_sents)
    train_ds = BertUDDataset(train_sents, tokenizer, vocabs, args.max_subwords)
    dev_ds = BertUDDataset(dev_sents, tokenizer, vocabs, args.max_subwords)
    print(f"train: {len(train_ds)} sentences ({train_ds.skipped} skipped as too long) | "
          f"dev: {len(dev_ds)} ({dev_ds.skipped} skipped)")

    # Everything the converter / Swift app needs besides the weights.
    tokenizer.save_pretrained(os.path.join(args.output, "tokenizer"))
    for name in LABEL_VOCABS:
        getattr(vocabs, name).save(os.path.join(args.output, f"{name}_vocab.json"))
    step = max(1, len(dev_ds) // 50)
    golden = [{k: dev_ds[i][k] for k in ("words", "input_ids", "word_index")}
              for i in range(0, len(dev_ds), step)][:50]
    with open(os.path.join(args.output, "tokenizer_golden.json"), "w", encoding="utf-8") as f:
        json.dump(golden, f, ensure_ascii=False, indent=1)

    pad_id = tokenizer.pad_token_id
    train_loader = DataLoader(train_ds, batch_size=args.batch_size, shuffle=True,
                              collate_fn=lambda b: collate(b, pad_id))
    dev_loader = DataLoader(dev_ds, batch_size=args.batch_size, shuffle=False,
                            collate_fn=lambda b: collate(b, pad_id))

    encoder = AutoModel.from_pretrained(args.base_model)
    encoder.config.save_pretrained(os.path.join(args.output, "encoder"))
    model = BertUDModel(
        encoder, num_upos=len(vocabs.upos), num_xpos=len(vocabs.xpos),
        num_feats=len(vocabs.feats), num_lemma_rules=len(vocabs.lemma_rule),
        num_deprel=len(vocabs.deprel), arc_mlp_dim=args.arc_mlp_dim,
        label_mlp_dim=args.label_mlp_dim, dropout=args.dropout,
        tag_feature_dim=args.tag_feature_dim,
        use_upos_feature=args.use_upos_feature,
        use_feats_feature=args.use_feats_feature,
        use_lemma_feature=args.use_lemma_feature,
    ).to(device)

    config = dict(vars(args))
    config.update({
        "num_upos": len(vocabs.upos), "num_xpos": len(vocabs.xpos),
        "num_feats": len(vocabs.feats), "num_lemma_rules": len(vocabs.lemma_rule),
        "num_deprel": len(vocabs.deprel),
    })
    with open(os.path.join(args.output, "config.json"), "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2)

    head_params = [p for n, p in model.named_parameters() if not n.startswith("encoder.")]
    optimizer = torch.optim.AdamW(
        [{"params": model.encoder.parameters(), "lr": args.encoder_lr},
         {"params": head_params, "lr": args.head_lr}],
        weight_decay=0.01,
    )
    total_steps = len(train_loader) * args.epochs
    scheduler = get_linear_schedule_with_warmup(
        optimizer, int(args.warmup_ratio * total_steps), total_steps)
    criterion = nn.CrossEntropyLoss(ignore_index=IGNORE_INDEX)

    best_las, stale = 0.0, 0
    for epoch in range(1, args.epochs + 1):
        started = time.time()
        model.train()
        running = {k: 0.0 for k in
                   ("total", "upos", "xpos", "feats", "lemma_rule", "arc", "label")}
        for batch in train_loader:
            batch = {k: v.to(device) for k, v in batch.items()}
            optimizer.zero_grad()
            total_loss, losses = compute_losses(_forward(model, batch), batch, criterion)
            total_loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
            scheduler.step()
            running["total"] += total_loss.item()
            for k, v in losses.items():
                running[k] += v.item()

        n_batches = len(train_loader)
        summary = " ".join(f"{k}={v / n_batches:.3f}" for k, v in running.items())
        m = evaluate(model, dev_loader, device, criterion)
        print(f"epoch {epoch:3d} | train: {summary}")
        print(f"           | dev: loss={m['loss']:.3f} upos={m['upos']:.4f} "
              f"xpos={m['xpos']:.4f} feats={m['feats']:.4f} "
              f"lemma={m['lemma_rule']:.4f} UAS={m['uas']:.4f} LAS={m['las']:.4f} "
              f"::: {time.time() - started:.0f}s")

        torch.save(model.state_dict(), os.path.join(args.output, "last.pt"))
        if m["las"] > best_las:
            best_las, stale = m["las"], 0
            torch.save(model.state_dict(), os.path.join(args.output, "best.pt"))
            print(f"  -> new best model saved (dev LAS={best_las:.4f})")
        else:
            stale += 1
            if stale >= args.patience:
                print("Early stopping: no improvement.")
                break

    print(f"Training complete. Best dev LAS: {best_las:.4f}")
    print(f"Checkpoints, vocabs, tokenizer and config saved to: {args.output}")


if __name__ == "__main__":
    main()
