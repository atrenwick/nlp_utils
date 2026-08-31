"""Training loop for the joint UPOS / XPOS / FEATS / lemma / dependency-parsing
model.

Runs as a plain Python (PyTorch) process on your Apple Silicon Mac, using
the MPS backend for GPU acceleration. Xcode is not involved at this stage --
it comes in afterwards, once the trained model is converted with
coremltools and dropped into an app as a .mlpackage.

Usage (run from the ud_trainer/ project root):

    python -m tagger_parser.train \
        --train data/en_ewt-ud-train.conllu \
        --dev data/en_ewt-ud-dev.conllu \
        --output out/tagger_parser

Notes on evaluation:
  - UPOS / XPOS / FEATS / lemma-rule accuracy are computed token-wise.
  - UAS (unlabeled attachment score) / LAS (labeled attachment score) are
    computed with a *greedy argmax* head choice for speed and simplicity.
    This does not guarantee a well-formed tree (no cycles, single root).
    For production inference, decode with a maximum spanning tree algorithm
    (Chu-Liu-Edmonds) over `arc_logits` instead -- ask if you'd like that
    decoder written up as part of the iOS-side inference code.
"""
import argparse
import json
import os

import torch
from torch.utils.data import DataLoader

from tagger_parser.data import (
    IGNORE_INDEX, collate_fn, load_dataset,
)
from tagger_parser.model import UDModel


def get_device():
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


def compute_losses(outputs, batch, criterion):
    losses = {}
    losses["upos"] = criterion(outputs["upos"].reshape(-1, outputs["upos"].size(-1)),
                                batch["upos_ids"].reshape(-1))
    losses["xpos"] = criterion(outputs["xpos"].reshape(-1, outputs["xpos"].size(-1)),
                                batch["xpos_ids"].reshape(-1))
    losses["feats"] = criterion(outputs["feats"].reshape(-1, outputs["feats"].size(-1)),
                                 batch["feats_ids"].reshape(-1))
    losses["lemma_rule"] = criterion(
        outputs["lemma_rule"].reshape(-1, outputs["lemma_rule"].size(-1)),
        batch["lemma_rule_ids"].reshape(-1),
    )

    arc_logits = outputs["arc"]  # [B, T, T]
    heads = batch["heads"]       # [B, T]
    losses["arc"] = criterion(arc_logits.reshape(-1, arc_logits.size(-1)), heads.reshape(-1))

    # Gather label logits at the gold head index for each dependent, then
    # score against the gold relation label (teacher forcing).
    label_logits = outputs["label"]  # [B, C, T, T]
    b, c, t, _ = label_logits.shape
    safe_heads = heads.clamp(min=0)
    idx = safe_heads.view(b, 1, t, 1).expand(-1, c, -1, 1)
    selected = torch.gather(label_logits, dim=3, index=idx).squeeze(3)  # [B, C, T]
    selected = selected.transpose(1, 2)  # [B, T, C]
    losses["label"] = criterion(selected.reshape(-1, c), batch["deprel_ids"].reshape(-1))

    total = sum(losses.values())
    return total, losses


@torch.no_grad()
def evaluate(model, loader, device, criterion):
    model.eval()
    totals = {"upos": 0, "xpos": 0, "feats": 0, "lemma_rule": 0, "uas": 0, "las": 0, "tokens": 0}
    loss_sum, n_batches = 0.0, 0

    for batch in loader:
        batch = {k: v.to(device) for k, v in batch.items()}
        outputs = model(batch["word_ids"], batch["char_ids"], batch["lengths"])
        total_loss, _ = compute_losses(outputs, batch, criterion)
        loss_sum += total_loss.item()
        n_batches += 1

        mask = batch["upos_ids"] != IGNORE_INDEX
        totals["tokens"] += mask.sum().item()

        for key in ("upos", "xpos", "feats", "lemma_rule"):
            preds = outputs[key].argmax(-1)
            gold = batch[f"{key}_ids"]
            totals[key] += (preds[mask] == gold[mask]).sum().item()

        # Mask self-loops (a word cannot be its own head) before argmax.
        arc_logits = outputs["arc"].clone()
        b, t, _ = arc_logits.shape
        eye = torch.eye(t, device=device, dtype=torch.bool).unsqueeze(0).expand(b, -1, -1)
        arc_logits.masked_fill_(eye, float("-inf"))
        head_preds = arc_logits.argmax(-1)  # [B, T]
        gold_heads = batch["heads"]
        head_mask = gold_heads != IGNORE_INDEX
        totals["uas"] += (head_preds[head_mask] == gold_heads[head_mask]).sum().item()

        safe_pred_heads = head_preds.clamp(min=0)
        c = outputs["label"].size(1)
        idx = safe_pred_heads.view(b, 1, t, 1).expand(-1, c, -1, 1)
        selected = torch.gather(outputs["label"], dim=3, index=idx).squeeze(3).transpose(1, 2)
        label_preds = selected.argmax(-1)
        correct_arc_and_label = (head_preds == gold_heads) & (label_preds == batch["deprel_ids"])
        totals["las"] += correct_arc_and_label[head_mask].sum().item()

    model.train()
    n = max(totals["tokens"], 1)
    metrics = {k: totals[k] / n for k in ("upos", "xpos", "feats", "lemma_rule", "uas", "las")}
    metrics["loss"] = loss_sum / max(n_batches, 1)
    return metrics


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--train", required=True, help="Training .conllu file")
    ap.add_argument("--dev", required=True, help="Development .conllu file")
    ap.add_argument("--output", required=True, help="Output directory for checkpoints/vocab")
    ap.add_argument("--batch_size", type=int, default=32)
    ap.add_argument("--epochs", type=int, default=100)
    ap.add_argument("--lr", type=float, default=2e-3)
    ap.add_argument("--min_word_freq", type=int, default=2)
    ap.add_argument("--word_emb_dim", type=int, default=100)
    ap.add_argument("--char_emb_dim", type=int, default=32)
    ap.add_argument("--char_num_filters", type=int, default=30)
    ap.add_argument("--encoder_hidden", type=int, default=256)
    ap.add_argument("--encoder_layers", type=int, default=3)
    ap.add_argument("--arc_mlp_dim", type=int, default=400)
    ap.add_argument("--label_mlp_dim", type=int, default=100)
    ap.add_argument("--dropout", type=float, default=0.33)
    ap.add_argument("--patience", type=int, default=10, help="Early-stopping patience in epochs")
    args = ap.parse_args()

    os.makedirs(args.output, exist_ok=True)
    device = get_device()
    print(f"Using device: {device}")

    train_ds, vocabs = load_dataset(args.train, build_vocabs=True, min_word_freq=args.min_word_freq)
    dev_ds, _ = load_dataset(args.dev, vocabs=vocabs)
    vocabs.save(args.output)

    word_pad_id, char_pad_id = vocabs.word.pad_id, vocabs.char.pad_id
    train_loader = DataLoader(
        train_ds, batch_size=args.batch_size, shuffle=True,
        collate_fn=lambda b: collate_fn(b, word_pad_id, char_pad_id),
    )
    dev_loader = DataLoader(
        dev_ds, batch_size=args.batch_size, shuffle=False,
        collate_fn=lambda b: collate_fn(b, word_pad_id, char_pad_id),
    )

    model = UDModel(
        word_vocab_size=len(vocabs.word), char_vocab_size=len(vocabs.char),
        num_upos=len(vocabs.upos), num_xpos=len(vocabs.xpos),
        num_feats=len(vocabs.feats), num_lemma_rules=len(vocabs.lemma_rule),
        num_deprel=len(vocabs.deprel), word_emb_dim=args.word_emb_dim,
        char_emb_dim=args.char_emb_dim, char_num_filters=args.char_num_filters,
        encoder_hidden=args.encoder_hidden, encoder_layers=args.encoder_layers,
        arc_mlp_dim=args.arc_mlp_dim, label_mlp_dim=args.label_mlp_dim,
        dropout=args.dropout, word_pad_id=word_pad_id, char_pad_id=char_pad_id,
    ).to(device)

    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, betas=(0.9, 0.9))
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
        optimizer, mode="max", factor=0.5, patience=3
    )
    criterion = torch.nn.CrossEntropyLoss(ignore_index=IGNORE_INDEX)

    config = dict(vars(args))
    config.update({
        "word_vocab_size": len(vocabs.word), "char_vocab_size": len(vocabs.char),
        "num_upos": len(vocabs.upos), "num_xpos": len(vocabs.xpos),
        "num_feats": len(vocabs.feats), "num_lemma_rules": len(vocabs.lemma_rule),
        "num_deprel": len(vocabs.deprel),
    })
    with open(os.path.join(args.output, "config.json"), "w") as f:
        json.dump(config, f, indent=2)

    best_las = 0.0
    epochs_without_improvement = 0

    for epoch in range(1, args.epochs + 1):
        model.train()
        running = {"total": 0.0, "upos": 0.0, "xpos": 0.0, "feats": 0.0,
                   "lemma_rule": 0.0, "arc": 0.0, "label": 0.0}
        for batch in train_loader:
            batch = {k: v.to(device) for k, v in batch.items()}
            optimizer.zero_grad()
            outputs = model(batch["word_ids"], batch["char_ids"], batch["lengths"])
            total_loss, losses = compute_losses(outputs, batch, criterion)
            total_loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 5.0)
            optimizer.step()

            running["total"] += total_loss.item()
            for k, v in losses.items():
                running[k] += v.item()

        n_batches = len(train_loader)
        train_summary = " ".join(f"{k}={v / n_batches:.3f}" for k, v in running.items())
        metrics = evaluate(model, dev_loader, device, criterion)
        scheduler.step(metrics["las"])

        print(f"epoch {epoch:3d} | train: {train_summary}")
        print(f"           | dev: loss={metrics['loss']:.3f} "
              f"upos={metrics['upos']:.4f} xpos={metrics['xpos']:.4f} "
              f"feats={metrics['feats']:.4f} lemma={metrics['lemma_rule']:.4f} "
              f"UAS={metrics['uas']:.4f} LAS={metrics['las']:.4f}")

        torch.save(model.state_dict(), os.path.join(args.output, "last.pt"))
        if metrics["las"] > best_las:
            best_las = metrics["las"]
            epochs_without_improvement = 0
            torch.save(model.state_dict(), os.path.join(args.output, "best.pt"))
            print(f"  -> new best model saved (dev LAS={best_las:.4f})")
        else:
            epochs_without_improvement += 1
            if epochs_without_improvement >= args.patience:
                print("Early stopping: no improvement.")
                break

    print(f"Training complete. Best dev LAS: {best_las:.4f}")
    print(f"Checkpoints, vocabs, and config saved to: {args.output}")


if __name__ == "__main__":
    main()
