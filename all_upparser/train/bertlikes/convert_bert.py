"""Convert a fine-tuned DistilBERT tagger/lemmatizer/parser checkpoint (from
train_bert.py) into a Core ML .mlpackage with FIXED input lengths.

Usage (from the project root, venv active):

    pip install coremltools transformers

    python -m tagger_parser.convert_bert \
        --useBest \
        --model_dir out/bert_tagger_parser \
        --output_name BertTaggerParser.mlpackage \
        --seq_len 128 \
        --max_words 96

Fixed lengths
-------------
Both inputs have a fixed size, so every shape-dependent operation in the
traced graph is a constant at conversion time. Shorter sentences are
padded, and the model works out the padding from the inputs themselves:

    input_ids   [1, seq_len]    int32. [CLS] + WordPiece subwords of every
                                word + [SEP], then padded with the tokenizer's
                                pad id (printed at the end; 0 for DistilBERT).
    word_index  [1, max_words]  int32. Position in input_ids of each word's
                                first subword; element 0 is the ROOT slot and
                                points at [CLS]. Padded with -1.

Outputs are the same six raw tensors, with the same names, as the BiLSTM
model, but sized for the padded length. Only the first n rows/columns are
meaningful, where n = number of words + 1 (the ROOT slot):

    upos/xpos/feats/lemma_rule_logits  [1, max_words, K]   -> rows [0, n)
    arc_logits                         [1, max_words, max_words]  -> [0, n) x [0, n)
    label_logits                       [1, num_deprel, max_words, max_words]

Padded head columns in arc_logits are already pushed to about -1e4, so an
argmax over a row can't pick a padding slot. Decoding is otherwise
unchanged (argmax + vocab lookup, apply_lemma_rule, Chu-Liu-Edmonds), run
over the n x n block.

A sentence that needs more than seq_len subwords, or has more than
max_words - 1 words, has to be split or truncated by the app.

coremltools / NumPy 2
---------------------
coremltools' torch `_cast` handler calls int() on one-element arrays, which
NumPy 2 rejects ("only 0-dimensional arrays can be converted to Python
scalars"). patch_coremltools_cast() below works around it. Alternatively
`pip install "numpy<2"` avoids the problem without a patch.

Encoder forward pass
--------------------
The DistilBERT forward pass is written out by hand (FixedLengthDistilBert)
using the trained weights, instead of calling the Hugging Face model. Its
mask-building code varies between transformers versions and uses ops
coremltools can't convert. Before converting, check_encoder() confirms the
hand-written version matches the Hugging Face output in PyTorch.

After converting, the script runs the Core ML model and the PyTorch model
on the same random input and prints the largest difference per output over
the valid region. fp16 differences of ~1e-2 are normal; large values mean
an op converted wrongly. Prediction only works on macOS.
"""
import argparse
import json
import math

import numpy as np
import torch
import torch.nn as nn
from transformers import AutoConfig, AutoModel, AutoTokenizer

from tagger_parser.train_bert import BertUDModel, gather_words

OUTPUT_NAMES = ["upos_logits", "xpos_logits", "feats_logits",
                "lemma_rule_logits", "arc_logits", "label_logits"]


def patch_coremltools_cast():
    """Make coremltools' int/float/bool casts accept one-element arrays.

    Rebinds `_cast` in coremltools' torch frontend. Constant inputs with
    ndim > 0 and a single element are converted through .item(); anything
    else goes to the original handler untouched.
    """
    try:
        import coremltools.converters.mil.frontend.torch.ops as torch_ops
        original_cast = torch_ops._cast
        get_inputs = torch_ops._get_inputs
        mb = torch_ops.mb
    except (ImportError, AttributeError) as exc:
        print(f"Could not apply the coremltools cast patch ({exc}); "
              "if conversion fails with 'only 0-dimensional arrays', "
              'try: pip install "numpy<2"')
        return

    def cast_compat(context, node, dtype, dtype_name):
        x = get_inputs(context, node, expected=1)[0]
        if x.can_be_folded_to_const() and np.ndim(x.val) > 0 and np.size(x.val) == 1:
            result = mb.const(val=dtype(np.asarray(x.val).item()), name=node.name)
            context.add(result, node.name)
            return
        original_cast(context, node, dtype, dtype_name)

    torch_ops._cast = cast_compat


class FixedLengthDistilBert(nn.Module):
    """DistilBERT's forward pass written out by hand for batch 1 and a fixed
    sequence length, reusing the trained encoder's own weights and layers.

    Why: Hugging Face's forward builds its attention mask with helper code
    that changes between transformers versions and uses ops coremltools
    can't convert (new_ones, vmap, ...). Here the mask is a plain additive
    bias and every shape is a Python constant, so the traced graph only
    contains linear / matmul / softmax / layer_norm / gelu / add.

    check_encoder() compares this against the Hugging Face forward before
    conversion, so a mistake here is caught in PyTorch, not in Core ML.
    """

    def __init__(self, encoder, seq_len):
        super().__init__()
        self.embeddings = encoder.embeddings
        self.layers = encoder.transformer.layer
        self.seq_len = seq_len
        self.dim = encoder.config.hidden_size
        self.n_heads = encoder.config.num_attention_heads
        self.head_dim = self.dim // self.n_heads
        self.register_buffer("position_ids", torch.arange(seq_len).unsqueeze(0),
                             persistent=False)

    def _split_heads(self, t):          # [1, S, D] -> [1, H, S, head_dim]
        return t.reshape(1, self.seq_len, self.n_heads, self.head_dim).transpose(1, 2)

    def _block(self, layer, x, bias):
        attn = layer.attention
        q = self._split_heads(attn.q_lin(x)) / math.sqrt(self.head_dim)
        k = self._split_heads(attn.k_lin(x))
        v = self._split_heads(attn.v_lin(x))
        weights = torch.softmax(torch.matmul(q, k.transpose(2, 3)) + bias, dim=-1)
        context = torch.matmul(weights, v).transpose(1, 2).reshape(1, self.seq_len, self.dim)
        sa_out = layer.sa_layer_norm(attn.out_lin(context) + x)
        ffn_out = layer.ffn.lin2(layer.ffn.activation(layer.ffn.lin1(sa_out)))
        return layer.output_layer_norm(ffn_out + sa_out)

    def forward(self, input_ids, attention_mask):
        emb = self.embeddings
        x = emb.LayerNorm(emb.word_embeddings(input_ids)
                          + emb.position_embeddings(self.position_ids))
        # 0 for real tokens, -1e4 for padding, broadcast over heads and queries
        bias = ((attention_mask.to(x.dtype) - 1.0) * 1e4)[:, None, None, :]
        for layer in self.layers:
            x = self._block(layer, x, bias)
        return x


class BertUDInference(nn.Module):
    """Single-sentence inference wrapper for fixed-length, padded inputs.

    Builds the attention mask from the padding in input_ids and the word
    mask from the -1 padding in word_index, so the Core ML model needs just
    two inputs. No dropout.
    """

    def __init__(self, trained: BertUDModel, pad_id: int, seq_len: int):
        super().__init__()
        self.trained = trained
        self.pad_id = pad_id
        self.bert = FixedLengthDistilBert(trained.encoder, seq_len)

    def forward(self, input_ids, word_index):
        m = self.trained
        attention_mask = (input_ids != self.pad_id).long()
        hidden = self.bert(input_ids, attention_mask)

        valid = word_index >= 0                                   # [1, T], True = real word
        word_valid = valid.to(hidden.dtype)
        # Padding slots (-1) must become a legal index. Multiplying by the 0/1
        # mask keeps everything integer; clamp() would not, because coremltools
        # lowers it to a float-only op and gather then rejects the float indices.
        safe_index = word_index * valid.long()                    # pad slots read [CLS]
        words = gather_words(hidden, safe_index)

        upos_logits = m.upos_head(words)
        xpos_logits = m.xpos_head(words)
        feats_logits = m.feats_head(words)
        lemma_logits = m.lemma_head(words)
        parser_input = m.build_parser_input(words, upos_logits, feats_logits, lemma_logits)

        arc_logits = m.arc_biaffine(m.arc_dep_mlp(parser_input),
                                     m.arc_head_mlp(parser_input))
        # 0 for real head columns, -1e4 for padding (plain arithmetic, no bool ops)
        arc_logits = arc_logits + ((word_valid - 1.0) * 1e4).unsqueeze(1)

        label_logits = m.label_biaffine(m.label_dep_mlp(parser_input),
                                         m.label_head_mlp(parser_input))
        return (upos_logits, xpos_logits, feats_logits, lemma_logits,
                arc_logits, label_logits)


def make_inputs(vocab_size, seq_len, max_words, n_subwords, n_words, pad_id):
    """Random padded inputs: n_subwords real ids (incl. specials), n_words word slots."""
    ids = torch.full((1, seq_len), pad_id, dtype=torch.long)
    ids[0, :n_subwords] = torch.randint(1000, vocab_size, (n_subwords,))
    word_index = torch.full((1, max_words), -1, dtype=torch.long)
    word_index[0, :n_words] = torch.arange(n_words)
    return ids, word_index


def check_encoder(hf_encoder, custom_encoder, vocab_size, seq_len, pad_id):
    """PyTorch-only sanity check: the hand-written encoder must match the
    Hugging Face forward pass on the real (non-padding) positions."""
    n_real = min(30, seq_len)
    ids, _ = make_inputs(vocab_size, seq_len, 2, n_subwords=n_real, n_words=2, pad_id=pad_id)
    mask = (ids != pad_id).long()
    with torch.no_grad():
        reference = hf_encoder(input_ids=ids, attention_mask=mask).last_hidden_state
        ours = custom_encoder(ids, mask)
    diff = (reference[:, :n_real] - ours[:, :n_real]).abs().max().item()
    print(f"Encoder check (hand-written vs Hugging Face forward): max abs diff {diff:.2e}")
    if diff > 1e-3:
        raise RuntimeError(
            "The hand-written DistilBERT forward pass doesn't match the Hugging Face "
            "one, so this transformers version differs from what FixedLengthDistilBert "
            "assumes. Don't convert; send me the diff and your transformers version.")


def verify(mlmodel, inference_model, vocab_size, seq_len, max_words, pad_id):
    n_words = 14
    ids, word_index = make_inputs(vocab_size, seq_len, max_words,
                                  n_subwords=30, n_words=n_words, pad_id=pad_id)
    with torch.no_grad():
        reference = inference_model(ids, word_index)
    try:
        predicted = mlmodel.predict({
            "input_ids": ids.numpy().astype(np.int32),
            "word_index": word_index.numpy().astype(np.int32),
        })
    except Exception as exc:  # pylint: disable=broad-exception-caught
        print(f"Skipping parity check (Core ML predict unavailable here): {exc}")
        return
    print("Parity check (max abs difference over the valid region, PyTorch vs Core ML):")
    n = n_words
    for name, ref in zip(OUTPUT_NAMES, reference):
        if name == "arc_logits":
            region = (slice(None), slice(n), slice(n))
        elif name == "label_logits":
            region = (slice(None), slice(None), slice(n), slice(n))
        else:
            region = (slice(None), slice(n))
        diff = np.abs(predicted[name][region] - ref.numpy()[region]).max()
        print(f"  {name:20s} {diff:.4f}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model_dir", required=True,
                     help="The --output directory used by train_bert.py")
    ap.add_argument("--useBest", action="store_true", help="Load best.pt")
    ap.add_argument("--useLast", action="store_true", help="Load last.pt")
    ap.add_argument("--output_name", required=True,
                     help="Name for the .mlpackage, written inside --model_dir")
    ap.add_argument("--seq_len", type=int, default=128,
                     help="Fixed length of input_ids, including [CLS] and [SEP] "
                          "(DistilBERT's hard limit is 512)")
    ap.add_argument("--max_words", type=int, default=96,
                     help="Fixed length of word_index, including the ROOT slot. "
                          "Must be at most seq_len - 1.")
    ap.add_argument("--min_ios", choices=["iOS15", "iOS16", "iOS17"], default="iOS16")
    args = ap.parse_args()

    if args.useBest:
        checkpoint_path = f"{args.model_dir}/best.pt"
    elif args.useLast:
        checkpoint_path = f"{args.model_dir}/last.pt"
    else:
        raise ValueError("You must specify either --useBest or --useLast")
    if args.max_words > args.seq_len - 1:
        raise ValueError("--max_words must be at most --seq_len - 1 "
                         "(every word needs a subword, plus [SEP])")

    import coremltools as ct  # lazy, so --help works without it installed
    patch_coremltools_cast()

    with open(f"{args.model_dir}/config.json", encoding="utf-8") as f:
        config = json.load(f)

    tokenizer = AutoTokenizer.from_pretrained(f"{args.model_dir}/tokenizer")
    pad_id = tokenizer.pad_token_id

    # Build the encoder from its saved config (no pretrained download) and
    # force eager attention: it lowers to ops Core ML converts reliably.
    encoder_config = AutoConfig.from_pretrained(f"{args.model_dir}/encoder")
    encoder = AutoModel.from_config(encoder_config, attn_implementation="eager")
    model = BertUDModel(
        encoder, num_upos=config["num_upos"], num_xpos=config["num_xpos"],
        num_feats=config["num_feats"], num_lemma_rules=config["num_lemma_rules"],
        num_deprel=config["num_deprel"], arc_mlp_dim=config["arc_mlp_dim"],
        label_mlp_dim=config["label_mlp_dim"], dropout=0.0,
        tag_feature_dim=config["tag_feature_dim"],
        use_upos_feature=config["use_upos_feature"],
        use_feats_feature=config["use_feats_feature"],
        use_lemma_feature=config["use_lemma_feature"],
    )
    model.load_state_dict(torch.load(checkpoint_path, map_location="cpu"))
    model.eval()

    vocab_size = encoder_config.vocab_size
    inference_model = BertUDInference(model, pad_id, args.seq_len).eval()
    check_encoder(model.encoder, inference_model.bert, vocab_size, args.seq_len, pad_id)

    example_ids, example_word_index = make_inputs(
        vocab_size, args.seq_len, args.max_words,
        n_subwords=18, n_words=10, pad_id=pad_id)
    traced = torch.jit.trace(inference_model, (example_ids, example_word_index),
                             check_trace=False)

    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, args.seq_len), dtype=np.int32),
            ct.TensorType(name="word_index", shape=(1, args.max_words), dtype=np.int32),
        ],
        outputs=[ct.TensorType(name=n) for n in OUTPUT_NAMES],
        minimum_deployment_target=getattr(ct.target, args.min_ios),
        compute_precision=ct.precision.FLOAT16,
        convert_to="mlprogram",
    )

    output_full = f"{args.model_dir}/{args.output_name}"
    mlmodel.save(output_full)
    print(f"Saved {output_full}")

    verify(mlmodel, inference_model, vocab_size, args.seq_len, args.max_words, pad_id)

    print("\nInput contract for the Swift app:")
    print(f"  input_ids  : length {args.seq_len}, pad with {pad_id}")
    print(f"  word_index : length {args.max_words}, pad with -1")
    print("  read only the first (words + 1) rows/columns of each output")
    print("\nAdd these to the Xcode project:")
    print(f"  {output_full}")
    for name in ("upos", "xpos", "feats", "deprel", "lemma_rule"):
        print(f"  {args.model_dir}/{name}_vocab.json")
    print(f"  {args.model_dir}/tokenizer/vocab.txt  (WordPiece vocabulary)")
    print(f"  {args.model_dir}/tokenizer/tokenizer_config.json  (casing / accent settings)")
    print(f"  {args.model_dir}/tokenizer_golden.json  (test fixtures for the Swift tokenizer)")


if __name__ == "__main__":
    main()