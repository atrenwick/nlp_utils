"""Convert a trained tagger/lemmatizer/parser checkpoint into a Core ML
.mlpackage.

Produces a model with FLEXIBLE sequence length (any sentence length, up to
--max_seq_len words, and any word length up to --max_word_len characters)
and float16 weights.

Runs as a plain Python process on your Mac -- not inside Xcode. The
resulting .mlpackage is what you drag into your Xcode project afterwards.

Usage (from the ud_trainer/ project root, with the venv active):

    pip install coremltools

    python -m tagger_parser.convert \
        --checkpoint out/tagger_parser/best.pt \
        --model_dir out/tagger_parser \
        --output out/tagger_parser/tagger_parser.mlpackage \
        --max_seq_len 256 \
        --max_word_len 32

NOTE: this script has been carefully reviewed but not run end-to-end against
a real coremltools install (this was written in a sandboxed environment
without network access to install coremltools/PyTorch together). If
conversion errors out, the traceback will point at exactly which op or
dtype coremltools couldn't handle -- paste it back and it's usually a small,
targeted fix rather than a rewrite.

What comes out of the model, and what doesn't:
    The converted model outputs six raw tensors -- upos_logits, xpos_logits,
    feats_logits, lemma_rule_logits, arc_logits, label_logits. It does NOT
    output tag names, a decoded lemma string, or a decoded dependency tree.
    Turning upos_logits into "NOUN" is an argmax + vocab lookup; turning
    lemma_rule_logits into an actual lemma string means applying the
    predicted edit-script rule to the input word (see
    tagger_parser/data.py::apply_lemma_rule for the exact logic to mirror in
    Swift); turning arc_logits into a valid dependency tree means running a
    maximum spanning tree decode (Chu-Liu-Edmonds) rather than a naive
    per-word argmax, which can produce cycles. All of that decoding logic
    still needs to be written on the Swift side.
"""
import argparse
import json

import numpy as np
import torch
import torch.nn as nn

from tagger_parser.data import Vocabs
from tagger_parser.model import UDModel


class UDModelInference(nn.Module):
    """Re-wires a trained UDModel for single-sentence (batch=1) inference,
    dropping the pack_padded_sequence/pad_packed_sequence machinery that's
    only needed to handle *padding* across a batch of multiple, differently
    -sized sentences during training. For a single, unpadded sentence
    there's nothing to pack -- the encoder LSTM can just run over it
    directly, which is also what lets the sequence length stay dynamic when
    this gets traced for Core ML conversion."""

    def __init__(self, trained: UDModel):
        super().__init__()
        self.char_encoder = trained.char_encoder
        self.word_embedding = trained.word_embedding
        self.input_proj = trained.input_proj
        self.encoder = trained.encoder
        self.upos_head = trained.upos_head
        self.xpos_head = trained.xpos_head
        self.feats_head = trained.feats_head
        self.lemma_head = trained.lemma_head
        self.arc_dep_mlp = trained.arc_dep_mlp
        self.arc_head_mlp = trained.arc_head_mlp
        self.arc_biaffine = trained.arc_biaffine
        self.label_dep_mlp = trained.label_dep_mlp
        self.label_head_mlp = trained.label_head_mlp
        self.label_biaffine = trained.label_biaffine

    def forward(self, word_ids, char_ids):
        word_emb = self.word_embedding(word_ids)
        char_repr = self.char_encoder(char_ids)
        combined = torch.cat([word_emb, char_repr], dim=-1)
        combined = torch.relu(self.input_proj(combined))

        enc_out, _ = self.encoder(combined)

        arc_dep = self.arc_dep_mlp(enc_out)
        arc_head = self.arc_head_mlp(enc_out)
        arc_logits = self.arc_biaffine(arc_dep, arc_head)

        label_dep = self.label_dep_mlp(enc_out)
        label_head = self.label_head_mlp(enc_out)
        label_logits = self.label_biaffine(label_dep, label_head)

        return (
            self.upos_head(enc_out), self.xpos_head(enc_out),
            self.feats_head(enc_out), self.lemma_head(enc_out),
            arc_logits, label_logits,
        )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkpoint", required=True, help="Path to best.pt (or last.pt)")
    ap.add_argument("--model_dir", required=True,
                     help="Directory containing config.json and *_vocab.json "
                          "(the --output directory you used when training)")
    ap.add_argument("--output", required=True, help="Output .mlpackage path")
    ap.add_argument("--max_seq_len", type=int, default=256,
                     help="Upper bound on words-per-sentence (including the ROOT "
                          "token at position 0, so this is real-words + 1) the "
                          "converted model will accept")
    ap.add_argument("--max_word_len", type=int, default=32,
                     help="Upper bound on characters-per-word the converted model will accept")
    ap.add_argument("--min_ios", choices=["iOS15", "iOS16", "iOS17"], default="iOS16",
                     help="Lower this if you need to support older iOS versions; "
                          "raise it if you hit an unsupported-op error and don't "
                          "need the wider compatibility.")
    args = ap.parse_args()

    import coremltools as ct  # imported lazily so `--help` works without it installed

    with open(f"{args.model_dir}/config.json") as f:
        config = json.load(f)
    vocabs = Vocabs.load(args.model_dir)

    model = UDModel(
        word_vocab_size=config["word_vocab_size"], char_vocab_size=config["char_vocab_size"],
        num_upos=config["num_upos"], num_xpos=config["num_xpos"],
        num_feats=config["num_feats"], num_lemma_rules=config["num_lemma_rules"],
        num_deprel=config["num_deprel"], word_emb_dim=config["word_emb_dim"],
        char_emb_dim=config["char_emb_dim"], char_num_filters=config["char_num_filters"],
        encoder_hidden=config["encoder_hidden"], encoder_layers=config["encoder_layers"],
        arc_mlp_dim=config["arc_mlp_dim"], label_mlp_dim=config["label_mlp_dim"],
        dropout=0.0, word_pad_id=vocabs.word.pad_id, char_pad_id=vocabs.char.pad_id,
    )
    state_dict = torch.load(args.checkpoint, map_location="cpu")
    model.load_state_dict(state_dict)
    model.eval()

    inference_model = UDModelInference(model)
    inference_model.eval()

    # This example input only shapes the trace; the actual accepted range at
    # runtime comes from the RangeDim bounds passed to ct.convert below.
    example_seq_len = min(16, args.max_seq_len)
    example_word_len = min(8, args.max_word_len)
    example_word_ids = torch.randint(
        0, config["word_vocab_size"], (1, example_seq_len), dtype=torch.long
    )
    example_char_ids = torch.randint(
        0, config["char_vocab_size"], (1, example_seq_len, example_word_len), dtype=torch.long
    )

    traced = torch.jit.trace(
        inference_model, (example_word_ids, example_char_ids), check_trace=False
    )

    # lower_bound=2 because position 0 is always the synthetic ROOT token,
    # so the shortest real sentence (one word) needs seq_len=2.
    seq_dim = ct.RangeDim(lower_bound=2, upper_bound=args.max_seq_len, default=example_seq_len)
    word_len_dim = ct.RangeDim(lower_bound=1, upper_bound=args.max_word_len, default=example_word_len)

    mlmodel = ct.convert(
        traced,
        inputs=[
            # seq_dim is reused (the same object) for both inputs' word-count
            # axis so coremltools ties them together as one dynamic
            # dimension that must agree at runtime.
            ct.TensorType(name="word_ids", shape=(1, seq_dim), dtype=np.int32),
            ct.TensorType(name="char_ids", shape=(1, seq_dim, word_len_dim), dtype=np.int32),
        ],
        outputs=[
            ct.TensorType(name="upos_logits"),
            ct.TensorType(name="xpos_logits"),
            ct.TensorType(name="feats_logits"),
            ct.TensorType(name="lemma_rule_logits"),
            ct.TensorType(name="arc_logits"),
            ct.TensorType(name="label_logits"),
        ],
        minimum_deployment_target=getattr(ct.target, args.min_ios),
        compute_precision=ct.precision.FLOAT16,
        convert_to="mlprogram",
    )

    mlmodel.save(args.output)
    print(f"Saved {args.output}")
    print(f"Also bundle these vocab files from {args.model_dir} into your Xcode app:")
    print("  word_vocab.json, char_vocab.json, upos_vocab.json, xpos_vocab.json,")
    print("  feats_vocab.json, deprel_vocab.json, lemma_rule_vocab.json")
    print("The model only outputs raw logits/scores -- decoding tags, lemmas, "
          "and a valid dependency tree (MST decode) is Swift-side logic.")


if __name__ == "__main__":
    main()
