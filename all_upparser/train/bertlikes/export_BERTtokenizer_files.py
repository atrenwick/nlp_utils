"""Write vocab.txt and wordpiece_settings.json from a saved tokenizer.json.

Recent transformers versions save the whole tokenizer in tokenizer.json and
no longer write vocab.txt. tokenizer.json is the authoritative source: the
vocabulary is model.vocab (token -> id) and the casing rules are in the
BertNormalizer entry. This script turns those into the two files the Swift
WordPieceTokenizer reads:

    vocab.txt                  one token per line, line number = id
    wordpiece_settings.json    do_lower_case, strip_accents,
                               tokenize_chinese_chars, unk_token (all resolved
                               to explicit values, so Swift never has to guess)

Usage:

    python export_BERTokenizer_files.py out/bert_tagger_parser/tokenizer

Swift:

    WordPieceTokenizer(vocabURL: <vocab.txt>, configURL: <wordpiece_settings.json>)
"""
import argparse
import json
import sys
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tokenizer_dir",
                     help="Folder containing tokenizer.json (the tokenizer/ folder "
                          "inside the train_bert.py output directory)")
    args = ap.parse_args()

    folder = Path(args.tokenizer_dir)
    spec = json.loads((folder / "tokenizer.json").read_text(encoding="utf-8"))

    # --- vocabulary -> vocab.txt -------------------------------------------
    model = spec["model"]
    if model.get("type") != "WordPiece":
        sys.exit(f"Expected a WordPiece model, found {model.get('type')!r}")
    vocab = model["vocab"]
    by_id = sorted(vocab.items(), key=lambda item: item[1])
    if [token_id for _, token_id in by_id] != list(range(len(by_id))):
        sys.exit("Token ids aren't contiguous from 0, so they can't be written as vocab.txt")
    if any("\n" in token for token in vocab):
        sys.exit("A token contains a newline, so it can't be written one-per-line")

    with open(folder / "vocab.txt", "w", encoding="utf-8", newline="\n") as f:
        for token, _ in by_id:
            f.write(token + "\n")

    # --- normalizer -> wordpiece_settings.json ------------------------------
    normalizer = spec.get("normalizer") or {}
    if normalizer.get("type") != "BertNormalizer":
        sys.exit(f"Expected a BertNormalizer, found {normalizer.get('type')!r}. "
                 "The Swift tokenizer only implements the BERT normalisation steps.")
    lowercase = bool(normalizer.get("lowercase", True))
    strip = normalizer.get("strip_accents")          # null means "follow lowercase"
    settings = {
        "do_lower_case": lowercase,
        "strip_accents": lowercase if strip is None else bool(strip),
        "tokenize_chinese_chars": bool(normalizer.get("handle_chinese_chars", True)),
        "unk_token": model.get("unk_token", "[UNK]"),
    }
    (folder / "wordpiece_settings.json").write_text(
        json.dumps(settings, indent=2) + "\n", encoding="utf-8")

    # --- things the Swift side assumes --------------------------------------
    for needed in ("[CLS]", "[SEP]", "[PAD]", settings["unk_token"]):
        if needed not in vocab:
            print(f"WARNING: {needed} is not in the vocabulary; the Swift init will throw")
    prefix = model.get("continuing_subword_prefix", "##")
    max_chars = model.get("max_input_chars_per_word", 100)
    if prefix != "##" or max_chars != 100:
        print(f"WARNING: prefix is {prefix!r} and max_input_chars_per_word is {max_chars}; "
              "pass continuingPrefix: / maxInputCharsPerWord: to WordPieceTokenizer.init")

    print(f"Wrote {folder / 'vocab.txt'} ({len(by_id)} tokens)")
    print(f"Wrote {folder / 'wordpiece_settings.json'}: {settings}")


if __name__ == "__main__":
    main()