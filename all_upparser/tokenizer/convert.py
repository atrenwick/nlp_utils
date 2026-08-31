"""Convert a trained tokenizer/segmenter checkpoint into a Core ML .mlpackage.

Produces a model with flexible sequence length up to --max_seq_length, and float16 weights.

This will take the output from training and make a .mlpackage which can be added to
an Xcode project afterwards.

Usage (from the  project root, with the venv active):

    pip install coremltools 

    python -m tokenizer.convert \
        --model_dir out/tokenizer \
        --useBest \
        --output_name witty_package_name \
        --max_seq_len 1024

NOTE: 
	--useBest to use model saved as best.pt in model_dir
	--useLast to use last saved .pt in model_dir
	-- model_dir expects the >folder< where the training script wrote output 
	   files  config.json and char_vocab.json 
"""
import argparse
import json

import numpy as np
import torch
import torch.nn as nn

from common.vocab import Vocab
from tokenizer.model import CharTokenizer


class CharTokenizerInference(nn.Module):
    """Re-wires a trained CharTokenizer for single-sequence (batch=1)
    inference, dropping the pack_padded_sequence/pad_packed_sequence
    machinery that's only needed to handle *padding* across a batch of
    multiple, differently-sized sequences during training. For a single,
    unpadded sequence there's nothing to pack -- the LSTM can just run over
    it directly, which is also what lets the sequence length stay dynamic
    when this gets traced for Core ML conversion."""

    def __init__(self, trained: CharTokenizer):
        super().__init__()
        self.embedding = trained.embedding
        self.lstm = trained.lstm
        self.classifier = trained.classifier

    def forward(self, char_ids):
        emb = self.embedding(char_ids)
        out, _ = self.lstm(emb)
        return self.classifier(out)


def main():
    ap = argparse.ArgumentParser()
    #ap.add_argument("--checkpoint", required=True, help="Path to best.pt (or last.pt)")
    ap.add_argument("--model_dir", required=True,
                     help="Directory containing config.json and char_vocab.json "
                          "(the --output directory you used when training)")
    
    ap.add_argument("--useBest", action="store_true", help="Load the best.pt checkpoint")
    ap.add_argument("--useLast", action="store_true", help="Load the last.pt checkpoint")
    
    ap.add_argument("--output_name", required=True, help="Output .mlpackage path")
    ap.add_argument("--max_seq_len", type=int, default=1024,
                     help="Upper bound on characters-per-call the converted model will accept")
    ap.add_argument("--min_ios", choices=["iOS15", "iOS16", "iOS17"], default="iOS16",
                     help="Lower this if you need to support older iOS versions; "
                          "raise it if you hit an unsupported-op error and don't "
                          "need the wider compatibility.")
    args = ap.parse_args()

    import coremltools as ct  # imported lazily so `--help` works without it installed

    with open(f"{args.model_dir}/config.json") as f:
        config = json.load(f)
    char_vocab = Vocab.load(f"{args.model_dir}/char_vocab.json")

    model = CharTokenizer(
        vocab_size=config["vocab_size"], char_emb_dim=config["char_emb_dim"],
        hidden_size=config["hidden_size"], num_layers=config["num_layers"],
        num_labels=config["num_labels"], dropout=0.0, pad_id=char_vocab.pad_id,
    )
    
    # Determine the checkpoint path to use
    if args.useBest:
        checkpoint_path = f"{args.model_dir}/best.pt"
    elif args.useLast:
        checkpoint_path = f"{args.model_dir}/last.pt"
    else:
        # Handle the case where neither flag is provided
        raise ValueError("You must specify either --useBest or --useLast")

    state_dict = torch.load(checkpoint_path, map_location="cpu")
    model.load_state_dict(state_dict)
    model.eval()

    inference_model = CharTokenizerInference(model)
    inference_model.eval()

    # This example input only shapes the trace; the actual accepted range at
    # runtime comes from the RangeDim bounds passed to ct.convert below.
    example_seq_len = min(64, args.max_seq_len)
    example_char_ids = torch.randint(0, config["vocab_size"], (1, example_seq_len), dtype=torch.long)

    traced = torch.jit.trace(inference_model, example_char_ids, check_trace=False)

    seq_dim = ct.RangeDim(lower_bound=1, upper_bound=args.max_seq_len, default=example_seq_len)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="char_ids", shape=(1, seq_dim), dtype=np.int32)],
        outputs=[ct.TensorType(name="logits")],
        minimum_deployment_target=getattr(ct.target, args.min_ios),
        compute_precision=ct.precision.FLOAT16,
        convert_to="mlprogram",
    )
    output_name_full = f"{args.model_dir}/{args.output_name}"
    mlmodel.save(output_name_full)
    print(f"Saved {output_name_full}")
    print(f"Import {args.output_name} and {args.model_dir}/char_vocab.json into the Xcode project")


if __name__ == "__main__":
    main()
