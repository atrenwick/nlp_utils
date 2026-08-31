"""Training loop for the character-level tokenizer / sentence-segmenter.

Runs as a plain Python (PyTorch) process on your Apple Silicon Mac, using
the MPS backend for GPU acceleration. This is NOT run inside Xcode -- Xcode
comes in later, when you drop the Core-ML-converted model into an app.

Usage (run from the ud_trainer/ project root):

    python -m tokenizer.train \
        --train data/train.conllu \
        --test data/test.conllu \
        --output out/tokenizer
"""
import argparse
import json
import os
from collections import Counter

import torch
from torch.utils.data import DataLoader

from common.conllu_io import read_conllu_sentences
from tokenizer.data import (
    NUM_LABELS, TokenizerDataset, build_char_vocab, chunk_stream,
    collate_fn, sentences_to_char_stream,
)
from tokenizer.model import CharTokenizer


def get_device():
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


def evaluate(model, loader, device):
    model.eval()
    total, correct = 0, 0
    total_loss, n_batches = 0.0, 0
    criterion = torch.nn.CrossEntropyLoss(ignore_index=-100)
    with torch.no_grad():
        for ids, labels, lengths in loader:
            ids, labels = ids.to(device), labels.to(device)
            logits = model(ids, lengths)
            loss = criterion(logits.reshape(-1, NUM_LABELS), labels.reshape(-1))
            total_loss += loss.item()
            n_batches += 1
            preds = logits.argmax(-1)
            mask = labels != -100
            correct += (preds[mask] == labels[mask]).sum().item()
            total += mask.sum().item()
    model.train()
    return total_loss / max(n_batches, 1), correct / max(total, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--train", required=True, help="Training .conllu file")
    ap.add_argument("--test", required=True, help="Test .conllu file for evaluation")
    ap.add_argument("--output", required=True, help="Output directory for checkpoints/vocab")
    ap.add_argument("--seq_len", type=int, default=256)
    ap.add_argument("--batch_size", type=int, default=32)
    ap.add_argument("--epochs", type=int, default=30)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--char_emb_dim", type=int, default=64)
    ap.add_argument("--hidden_size", type=int, default=128)
    ap.add_argument("--num_layers", type=int, default=2)
    ap.add_argument("--dropout", type=float, default=0.3)
    ap.add_argument("--patience", type=int, default=5, help="Early-stopping patience in epochs")
    args = ap.parse_args()

    os.makedirs(args.output, exist_ok=True)
    device = get_device()
    print(f"Using device: {device}")

    train_sents = read_conllu_sentences(args.train)
    test_sents = read_conllu_sentences(args.test)

    train_chars, train_labels = sentences_to_char_stream(train_sents)
    test_chars, test_labels = sentences_to_char_stream(test_sents)

    char_vocab = build_char_vocab(train_chars)
    char_vocab.save(os.path.join(args.output, "char_vocab.json"))

    train_examples = chunk_stream(train_chars, train_labels, args.seq_len)
    test_examples = chunk_stream(test_chars, test_labels, args.seq_len)

    train_ds = TokenizerDataset(train_examples, char_vocab)
    test_ds = TokenizerDataset(test_examples, char_vocab)

    pad_id = char_vocab.pad_id
    train_loader = DataLoader(
        train_ds, batch_size=args.batch_size, shuffle=True,
        collate_fn=lambda b: collate_fn(b, pad_id),
    )
    test_loader = DataLoader(
        test_ds, batch_size=args.batch_size, shuffle=False,
        collate_fn=lambda b: collate_fn(b, pad_id),
    )

    model = CharTokenizer(
        vocab_size=len(char_vocab), char_emb_dim=args.char_emb_dim,
        hidden_size=args.hidden_size, num_layers=args.num_layers,
        num_labels=NUM_LABELS, dropout=args.dropout, pad_id=pad_id,
    ).to(device)

    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr)

    # The label distribution here is heavily skewed: most characters are
    # "inside a token" (class 0), and only a small fraction are boundaries.
    # An unweighted loss lets the model get a deceptively good accuracy
    # number just by always predicting the majority class -- weighting by
    # inverse class frequency forces boundary characters to actually matter.
    label_counts = Counter(train_labels)
    total_labels = sum(label_counts.values())
    class_weights = torch.tensor(
        [total_labels / (NUM_LABELS * label_counts.get(c, 1)) for c in range(NUM_LABELS)],
        dtype=torch.float32, device=device,
    )
    print(f"Training label distribution: {dict(sorted(label_counts.items()))}")
    print(f"Class weights: {class_weights.tolist()}")

    criterion = torch.nn.CrossEntropyLoss(weight=class_weights, ignore_index=-100)

    config = dict(vars(args))
    config.update({"vocab_size": len(char_vocab), "num_labels": NUM_LABELS})
    with open(os.path.join(args.output, "config.json"), "w") as f:
        json.dump(config, f, indent=2)

    best_acc = 0.0
    epochs_without_improvement = 0

    for epoch in range(1, args.epochs + 1):
        model.train()
        running_loss = 0.0
        for ids, labels, lengths in train_loader:
            ids, labels = ids.to(device), labels.to(device)
            optimizer.zero_grad()
            logits = model(ids, lengths)
            loss = criterion(logits.reshape(-1, NUM_LABELS), labels.reshape(-1))
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 5.0)
            optimizer.step()
            running_loss += loss.item()

        train_loss = running_loss / len(train_loader)
        test_loss, test_acc = evaluate(model, test_loader, device)
        print(f"epoch {epoch:3d} | train_loss {train_loss:.4f} | "
              f"test_loss {test_loss:.4f} | test_char_acc {test_acc:.4f}")

        torch.save(model.state_dict(), os.path.join(args.output, "last.pt"))
        if test_acc > best_acc:
            best_acc = test_acc
            epochs_without_improvement = 0
            torch.save(model.state_dict(), os.path.join(args.output, "best.pt"))
            print(f"  -> new best model saved (test_char_acc={best_acc:.4f})")
        else:
            epochs_without_improvement += 1
            if epochs_without_improvement >= args.patience:
                print("Early stopping: no improvement.")
                break

    print(f"Training complete. Best test char accuracy: {best_acc:.4f}")
    print(f"Checkpoints and vocab saved to: {args.output}")


if __name__ == "__main__":
    main()