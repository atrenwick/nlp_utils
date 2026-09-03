#!/usr/bin/env python3
"""
convert_lemmatizer.py

Converts the trained char-seq2seq lemmatizer (lemmatizer/train.py output)
into 2 Core ML models to add to an Xcode project:

    LemmatizerEncoder.mlpackage      -- encodes a word's characters + UPOS
    LemmatizerDecoderStep.mlpackage  -- runs ONE autoregressive decode step

As an autoregressive decoder, the Decoder will feed its own previous output
back in as the next input, looping until either <eos> or MAX_SRC_LEN.
Easy implementation in Swift + Core ML, to post-conversion hangs, memory bloat
1 - run encoder once, then loop decoder steps. 
2 - use fixed input length for both models : pad all words to MAX_SRC_LEN
and make explicit boolean mask, which excludes padding from attention.

Usage:
    python3 convert_lemmatizer.py --target_dir ./lemmatizer_out \
        --useBest


NOTE: when run on iOS, words longer than MAX_SRC_LEN characters get truncated 
then get passed to encoder in Swift.
"""

import argparse
import json
import os
import shutil

import coremltools as ct
import torch
import torch.nn as nn
from typing import Tuple, Dict, Any

from lemmatizer.model import Seq2SeqLemmatizer

MAX_SRC_LEN = 40     
# FIXED length -- every word is padded/truncated to this char len, then sent
# to encoder


def load_model_and_meta(target_dir: str) -> Tuple['Seq2SeqLemmatizer', Dict[str, Any]]:
    """Loads the lemmatizer model and its associated vocabulary metadata from disk.

    This function expects a directory containing two specific files:
    1. `lemma_vocabs.json`: A JSON file containing the character and UPOS vocabularies.
    2. `best_lemmatizer.pt`: A PyTorch checkpoint containing the model state 
       and training hyperparameters.

    The function reconstructs the `Seq2SeqLemmatizer` architecture using the 
       vocabulary sizes and hyperparameters found in the checkpoint before 
       loading the trained weights.

    Args:
        target_dir (str): The path to the directory containing the model 
            checkpoint and vocabulary JSON file.

    Returns:
        Tuple['Seq2SeqLemmatizer', Dict[str, Any]]: A tuple containing:
            - model (Seq2SeqLemmatizer): The initialized and weight-loaded 
                model set to evaluation mode.
            - vocabs (Dict[str, Any]): The dictionary containing the 
                'char' and 'upos' vocabulary lists.

    Raises:
        FileNotFoundError: If `lemma_vocabs.json` or `best_lemmatizer.pt` 
            cannot be found in the target directory.
        json.JSONDecodeError: If the vocabulary JSON file is malformed.
        RuntimeError: If the model state dictionary is incompatible with 
            the Seq2SeqLemmatizer architecture.
    """
    # Load vocabulary metadata
    vocab_path = os.path.join(target_dir, "lemma_vocabs.json")
    with open(vocab_path, encoding="utf-8") as f:
        vocabs = json.load(f)
    
    num_chars = len(vocabs["char"])
    num_upos = len(vocabs["upos"])

    # Load PyTorch checkpoint
    ckpt_path = os.path.join(target_dir, "best_lemmatizer.pt")
    ckpt = torch.load(ckpt_path, map_location="cpu")
    train_args = ckpt["args"]

    # Instantiate model using hyperparams from the checkpoint
    model = Seq2SeqLemmatizer(
        num_chars=num_chars, 
        num_upos=num_upos,
        enc_hidden=train_args.get("enc_hidden", 128),
        dec_hidden=train_args.get("dec_hidden", 256),
        dropout=0.0, # Set to 0.0 for inference
    )
    
    # Load weights and set to evaluation mode
    model.load_state_dict(ckpt["model_state"])
    model.eval()
    
    return model, vocabs



def strip_padding_idx(embed: nn.Embedding) -> nn.Embedding:
    """Returns a plain nn.Embedding with the exact same weights as `embed`, but
    with padding_idx=None.

    padding_idx only affects gradients during training (it zeroes backprop for 
    that row) — it has zero effect on the forward pass. Therefore, this is a 
    value-preserving copy for inference and tracing purposes only.

    Why this matters for conversion:
        coremltools warns "Core ML embedding (gather) layer does not support 
        any inputs besides the weights and indices. Those given will be ignored." 
        when tracing an nn.Embedding that has padding_idx set. The extra 
        padding_idx metadata baked into the traced graph appears to trigger 
        subsequent 'int' op conversion errors. Embeddings without padding_idx 
        trace as a plain gather with no extra baggage.

    Args:
        embed (nn.Embedding): The original embedding layer containing 
            padding_idx metadata.

    Returns:
        nn.Embedding: A new embedding layer with identical weights but 
            padding_idx set to None.
    """
    plain = nn.Embedding(embed.num_embeddings, embed.embedding_dim, padding_idx=None)
    plain.weight = embed.weight
    return plain

def lstm_cell_step(
    x: torch.Tensor, 
    h: torch.Tensor, 
    c: torch.Tensor, 
    w_ih: torch.Tensor, 
    w_hh: torch.Tensor, 
    b_ih: torch.Tensor, 
    b_hh: torch.Tensor, 
    H: int
) -> Tuple[torch.Tensor, torch.Tensor]:
    """Performs one LSTM cell step using raw tensor operations.

    This function implements the LSTM equations directly using matmul, 
    static slicing, sigmoid, and tanh. It bypasses `nn.LSTM` and `nn.LSTMCell` 
    to avoid `NotImplementedError`, memory explosion, and hangs caused by 
    the `aten::unsafe_chunk` operator during Core ML conversion.

    The math is numerically identical to what PyTorch's built-in LSTM 
    computes internally.

    Gates Mapping:
        - Index 0 to H-1: Input gate (i)
        - Index H to 2H-1: Forget gate (f)
        - Index 2H to 3H-1: Cell candidate (g)
        - Index 3H to 4H-1: Output gate (o)

    Args:
        x (torch.Tensor): Input tensor. 
            Shape: (batch, in_dim), Dtype: torch.float32.
        h (torch.Tensor): Previous hidden state. 
            Shape: (batch, H), Dtype: torch.float32.
        c (torch.Tensor): Previous cell state. 
            Shape: (batch, H), Dtype: torch.float32.
        w_ih (torch.Tensor): Input-to-hidden weight matrix. 
            Shape: (4*H, in_dim), Dtype: torch.float32.
        w_hh (torch.Tensor): Hidden-to-hidden weight matrix. 
            Shape: (4*H, H), Dtype: torch.float32.
        b_ih (torch.Tensor): Input-to-hidden bias. 
            Shape: (4*H,), Dtype: torch.float32.
        b_hh (torch.Tensor): Hidden-to-hidden bias. 
            Shape: (4*H,), Dtype: torch.float32.
        H (int): The hidden state dimensionality.

    Returns:
        Tuple[torch.Tensor, torch.Tensor]: A tuple containing:
            - h_new (torch.Tensor): The updated hidden state. Shape: (batch, H).
            - c_new (torch.Tensor): The updated cell state. Shape: (batch, H).
    """
    # Compute all four gates in one large matrix multiplication
    gates = x.matmul(w_ih.t()) + h.matmul(w_hh.t()) + b_ih + b_hh
    
    # Slice the gates tensor to extract i, f, g, and o
    i_gate = torch.sigmoid(gates[:, 0 * H:1 * H])
    f_gate = torch.sigmoid(gates[:, 1 * H:2 * H])
    g_gate = torch.tanh(gates[:, 2 * H:3 * H])
    o_gate = torch.sigmoid(gates[:, 3 * H:4 * H])
    
    # Update cell state and compute new hidden state
    c_new = f_gate * c + i_gate * g_gate
    h_new = o_gate * torch.tanh(c_new)
    
    return h_new, c_new
    


class EncoderWrapper(nn.Module):
    """Wrap Seq2SeqLemmatizer's encoder and UPOS conditioning for Core ML tracing.

    This wrapper replaces the standard PyTorch bidirectional LSTM with a manual 
    step-by-step loop using `lstm_cell_step`. This is done because `pack_padded_sequence` 
    and certain LSTM implementations do not trace cleanly for Core ML, often 
    causing "RangeDim" hangs or conversion failures.

    By unrolling the loop during tracing, this class produces a static graph 
    that is numerically identical to a native `nn.LSTM` but compatible with 
    the Core ML converter.

    Attributes:
        char_embed (nn.Embedding): Embedding layer for input characters.
        upos_embed (nn.Embedding): Embedding layer for UPOS tags.
        init_proj (nn.Linear): Projection layer to initialize the decoder state.
        enc_hidden (int): The hidden size of the encoder LSTM.
        w_ih_f (torch.Tensor): Forward LSTM input-hidden weights.
        w_hh_f (torch.Tensor): Forward LSTM hidden-hidden weights.
        b_ih_f (torch.Tensor): Forward LSTM input-hidden bias.
        b_hh_f (torch.Tensor): Forward LSTM hidden-hidden bias.
        w_ih_b (torch.Tensor): Backward LSTM input-hidden weights.
        w_hh_b (torch.Tensor): Backward LSTM hidden-hidden weights.
        b_ih_b (torch.Tensor): Backward LSTM input-hidden bias.
        b_hh_b (torch.Tensor): Backward LSTM hidden-hidden bias.
    """

    def __init__(self, model: 'Seq2SeqLemmatizer'):
        """Initializes the wrapper by extracting weights from the main model.

        Args:
            model (Seq2SeqLemmatizer): The full sequence-to-sequence model 
                containing the encoder and embedding components.
        """
        super().__init__()
        self.char_embed = strip_padding_idx(model.char_embed)
        self.upos_embed = strip_padding_idx(model.upos_embed)
        self.init_proj = model.init_proj

        enc = model.encoder  # nn.LSTM(char_emb, enc_hidden, bidirectional=True), 1 layer
        
        # Register weights as buffers to treat them as constants in the Core ML graph.
        # Forward weights
        self.register_buffer("w_ih_f", enc.weight_ih_l0.detach().clone())
        self.register_buffer("w_hh_f", enc.weight_hh_l0.detach().clone())
        self.register_buffer("b_ih_f", enc.bias_ih_l0.detach().clone())
        self.register_buffer("b_hh_f", enc.bias_hh_l0.detach().clone())
        
        # Backward weights
        self.register_buffer("w_ih_b", enc.weight_ih_l0_reverse.detach().clone())
        self.register_buffer("w_hh_b", enc.weight_hh_l0_reverse.detach().clone())
        self.register_buffer("b_ih_b", enc.bias_ih_l0_reverse.detach().clone())
        self.register_buffer("b_hh_b", enc.bias_hh_l0_reverse.detach().clone())
        
        self.enc_hidden = enc.hidden_size

    def forward(
        self, 
        src: torch.Tensor, 
        mask: torch.Tensor, 
        upos: torch.Tensor
    ) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        """Performs the encoding process and prepares the decoder initialization.

        Args:
            src (torch.Tensor): Padded character IDs.
                Shape: (1, MAX_SRC_LEN), Dtype: torch.int64.
            mask (torch.Tensor): Binary mask (1 for real characters, 0 for padding).
                Shape: (1, MAX_SRC_LEN), Dtype: torch.int64.
            upos (torch.Tensor): Universal Part-of-Speech tag ID.
                Shape: (1,), Dtype: torch.int64.

        Returns:
            Tuple[torch.Tensor, torch.Tensor, torch.Tensor]: A tuple containing:
                - enc_out (torch.Tensor): The concatenated bidirectional hidden states 
                    for each timestep. Shape: (1, MAX_SRC_LEN, 2 * enc_hidden), 
                    Dtype: torch.float32.
                - init_h (torch.Tensor): Initial hidden state for the decoder.
                    Shape: (1, dec_hidden), Dtype: torch.float32.
                - init_c (torch.Tensor): Initial cell state for the decoder.
                    Shape: (1, dec_hidden), Dtype: torch.float32.
        """
        mask_float = mask.float()
        emb = self.char_embed(src)  # (1, L, E)
        
        B = 1
        L = MAX_SRC_LEN
        H = self.enc_hidden

        # --- Forward direction: t = 0 .. L-1 -----------------------------
        h_f = torch.zeros((B, H), dtype=emb.dtype)
        c_f = torch.zeros((B, H), dtype=emb.dtype)
        forward_outs = []
        for t in range(L): 
            # This loop is unrolled during torch.jit.trace
            h_f, c_f = lstm_cell_step(
                emb[:, t, :], h_f, c_f, self.w_ih_f, self.w_hh_f, self.b_ih_f, self.b_hh_f, H
            )
            forward_outs.append(h_f)

        # --- Backward direction: t = L-1 .. 0 -----------------------------
        h_b = torch.zeros((B, H), dtype=emb.dtype)
        c_b = torch.zeros((B, H), dtype=emb.dtype)
        backward_outs = [None] * L
        for t in range(L - 1, -1, -1):
            h_b, c_b = lstm_cell_step(
                emb[:, t, :], h_b, c_b, self.w_ih_b, self.w_hh_b, self.b_ih_b, self.b_hh_b, H
            )
            backward_outs[t] = h_b

        # Concatenate forward and backward states to match nn.LSTM bidirectional convention
        enc_out = torch.stack(
            [torch.cat([forward_outs[t], backward_outs[t]], dim=-1) for t in range(L)],
            dim=1,
        )  # (1, L, 2H)

        # Zero out padded positions to prevent leakage into attention context
        enc_out = enc_out * mask_float.unsqueeze(-1)

        # Prepare final state for decoder initialization
        # h_cat contains the final hidden state of the forward pass and 
        # the final hidden state of the backward pass.
        h_cat = torch.cat([h_f, h_b], dim=-1)  # (1, 2H)

        upos_e = self.upos_embed(upos)
        init_h = torch.tanh(self.init_proj(torch.cat([h_cat, upos_e], dim=-1)))
        init_c = torch.zeros_like(init_h)
        
        return enc_out, init_h, init_c



class DecoderStepWrapper(nn.Module):
    """A wrapper for a single autoregressive decoding step.

    Class  designed to be called in a loop (e.g., from Swift/Core ML) to 
    generate characters one by one. It manually executes the decoder's LSTM 
    cell logic via `lstm_cell_step` to ensure compatibility with the tracing 
    process and Core ML's graph representation.

    Attributes:
        char_embed (nn.Embedding): Embedding layer for characters.
        attention (nn.Module): The attention mechanism used to query encoder outputs.
        out_proj (nn.Linear): Linear layer to project hidden state and context to logits.
        dec_hidden (int): The dimensionality of the decoder's hidden state.
        w_ih (torch.Tensor): Input-hidden weights for the LSTM cell.
        w_hh (torch.Tensor): Hidden-hidden weights for the LSTM cell.
        b_ih (torch.Tensor): Input-hidden bias for the LSTM cell.
        b_hh (torch.Tensor): Hidden-hidden bias for the LSTM cell.
    """

    def __init__(self, model: 'Seq2SeqLemmatizer'):
        """Initializes the wrapper by extracting components from the main model.

        Args:
            model (Seq2SeqLemmatizer): The full sequence-to-sequence model 
                containing the encoder and decoder components.
        """
        super().__init__()
        self.char_embed = strip_padding_idx(model.char_embed)
        self.attention = model.attention
        self.out_proj = model.out_proj
		
        cell = model.decoder_cell  # nn.LSTMCell(char_emb, dec_hidden)
        
        # Weights are registered as buffers to ensure they are treated as constants 
        # during Core ML conversion and not as trainable parameters.
        self.register_buffer("w_ih", cell.weight_ih.detach().clone())
        self.register_buffer("w_hh", cell.weight_hh.detach().clone())
        self.register_buffer("b_ih", cell.bias_ih.detach().clone())
        self.register_buffer("b_hh", cell.bias_hh.detach().clone())
        self.dec_hidden = cell.hidden_size

    def forward(
        self, 
        cur_char: torch.Tensor, 
        h: torch.Tensor, 
        c: torch.Tensor, 
        enc_out: torch.Tensor, 
        mask: torch.Tensor
    ) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        """Performs a single forward pass of the decoder step.

        Args:
            cur_char (torch.Tensor): Previous output character ID.
                Shape: (1,), Dtype: torch.int64.
            h (torch.Tensor): Current decoder hidden state.
                Shape: (1, dec_hidden), Dtype: torch.float32.
            c (torch.Tensor): Current decoder cell state.
                Shape: (1, dec_hidden), Dtype: torch.float32.
            enc_out (torch.Tensor): Encoder output tensors.
                Shape: (1, MAX_SRC_LEN, enc_out_dim), Dtype: torch.float32.
            mask (torch.Tensor): Attention mask for the source sequence.
                Shape: (1, MAX_SRC_LEN), Dtype: torch.int64.

        Returns:
            Tuple[torch.Tensor, torch.Tensor, torch.Tensor]: A tuple containing:
                - logits (torch.Tensor): The predicted character distribution.
                - new_h (torch.Tensor): Updated hidden state for the next step.
                - new_c (torch.Tensor): Updated cell state for the next step.
        """
        mask_bool = mask.bool()
        emb = self.char_embed(cur_char)
        
        # Manually execute LSTM step logic
        new_h, new_c = lstm_cell_step(
            emb, h, c, self.w_ih, self.w_hh, self.b_ih, self.b_hh, self.dec_hidden
        )
        
        # Calculate context via attention mechanism
        context, _ = self.attention(new_h, enc_out, mask_bool)
        
        # Combine hidden state and context to predict the next character
        logits = self.out_proj(torch.cat([new_h, context], dim=-1))
        
        return logits, new_h, new_c


def convert_encoder(model: torch.nn.Module, target_dir: str) -> None:
    """Converts a PyTorch encoder model to a Core ML model (.mlpackage).

    Wrap the provided model in an `EncoderWrapper`, trace the 
    execution graph using TorchScript with sample input tensors, and convert 
    the result into a mlpackage for iOS 16+.

    Args:
        model (torch.nn.Module): The PyTorch model containing the encoder logic.
        target_dir (str): Path to the directory where `.mlpackage` will be saved 

    Returns:
        None

    Raises:
        RuntimeError: If the torch.jit.trace or ct.convert process fails due to 
            unsupported operations or tensor shape mismatches.
        OSError: If the target directory is inaccessible or the model cannot 
            be saved to disk.
    """
    wrapper = EncoderWrapper(model).eval()

    # Define example inputs for TorchScript tracing
    example_src = torch.randint(4, 30, (1, MAX_SRC_LEN), dtype=torch.long)
    example_mask = torch.ones((1, MAX_SRC_LEN), dtype=torch.int64)
    example_upos = torch.tensor([1], dtype=torch.long)
    
    # Trace the model to create a Graph representation
    traced = torch.jit.trace(wrapper, (example_src, example_mask, example_upos))

    # Convert the traced model to Core ML format
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="src", shape=(1, MAX_SRC_LEN), dtype=int),
            ct.TensorType(name="mask", shape=(1, MAX_SRC_LEN), dtype=int),
            ct.TensorType(name="upos", shape=(1,), dtype=int),
        ],
        outputs=[
            ct.TensorType(name="enc_out"),
            ct.TensorType(name="init_h"),
            ct.TensorType(name="init_c"),
        ],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
        compute_precision=ct.precision.FLOAT32,
    )

    path = os.path.join(target_dir, "LemmatizerEncoder.mlpackage")
    mlmodel.save(path)
    print(f"[saved] {path}")



def convert_decoder_step(model: torch.nn.Module, target_dir: str) -> None:
    """Converts a PyTorch decoder step model to a Core ML model (.mlpackage).

    This function wraps the provided model in a `DecoderStepWrapper`, traces it 
    using TorchScript with example inputs, and then converts it to an ML Program 
    optimized for iOS 16+. The resulting model is saved to the specified target directory.

    Args:
        model (torch.nn.Module): The PyTorch model containing the decoder logic,  
            with attributes `attention.W` for input features, and `dec_hidden_size`
        target_dir (str): The file system path to the directory where the 
            converted `.mlpackage` should be saved.

    Returns:
        None

    Raises:
        RuntimeError: If the torch.jit.trace or ct.convert process fails.
        OSError: If the target directory is inaccessible or the model cannot be saved.
    """
    wrapper = DecoderStepWrapper(model).eval()

    enc_out_dim = model.attention.W.in_features
    dec_hidden = model.dec_hidden_size

    # Define example inputs for TorchScript tracing
    example_cur = torch.tensor([2], dtype=torch.long)  # e.g. <s> id
    example_h = torch.zeros((1, dec_hidden), dtype=torch.float32)
    example_c = torch.zeros((1, dec_hidden), dtype=torch.float32)
    example_enc_out = torch.zeros((1, MAX_SRC_LEN, enc_out_dim), dtype=torch.float32)
    example_mask = torch.ones((1, MAX_SRC_LEN), dtype=torch.int64)

    # Trace the model to create a Graph representation
    traced = torch.jit.trace(wrapper, (example_cur, example_h, example_c, example_enc_out, example_mask))

    # Convert the traced model to Core ML format
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="cur_char", shape=(1,), dtype=int),
            ct.TensorType(name="h", shape=(1, dec_hidden), dtype=float),
            ct.TensorType(name="c", shape=(1, dec_hidden), dtype=float),
            ct.TensorType(name="enc_out", shape=(1, MAX_SRC_LEN, enc_out_dim), dtype=float),
            ct.TensorType(name="mask", shape=(1, MAX_SRC_LEN), dtype=int),
        ],
        outputs=[
            ct.TensorType(name="logits"),
            ct.TensorType(name="new_h"),
            ct.TensorType(name="new_c"),
        ],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
        compute_precision=ct.precision.FLOAT32,
    )
    
    path = os.path.join(target_dir, "LemmatizerDecoderStep.mlpackage")
    mlmodel.save(path)
    print(f"[saved] {path}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target_dir", required=True,
                     help="Directory containing config.json and char_vocab.json "
                          "(the --output directory you used when training)")
    
    ap.add_argument("--useBest", action="store_true", help="Load the best.pt checkpoint")
    ap.add_argument("--useLast", action="store_true", help="Load the last.pt checkpoint")
    args = ap.parse_args()
    os.makedirs(args.target_dir, exist_ok=True)

    # Determine the checkpoint path to use
    if args.useBest:
        checkpoint_path = f"{args.target_dir}/best.pt"
    elif args.useLast:
        checkpoint_path = f"{args.target_dir}/last.pt"
    else:
        # Handle the case where neither flag is provided
        raise ValueError("You must specify either --useBest or --useLast")


    print("[info] loading trained model ...")
    model, vocabs = load_model_and_meta(args.target_dir)

    print("[info] converting encoder ...")
    convert_encoder(model, args.target_dir)

    print("[info] converting decoder step ...")
    convert_decoder_step(model, args.target_dir)

    print("[info] copying vocab + dictionary resources ...")
    for fname in ["lemma_vocabs.json", "lemma_dict.json"]:
        src_path = os.path.join(args.target_dir, fname)
        if os.path.exists(src_path):
            if os.path.join(args.target_dir, fname) != src_path:
                shutil.copy(src_path, os.path.join(args.target_dir, fname))
            else:
                print("No need to copy……")
        else:
            print(f"[warn] {fname} not found in {args.target_dir}, skipping.")

    print("\n[done] drag these into your Xcode project's target:")
    print(f"  {os.path.join(args.target_dir, 'LemmatizerEncoder.mlpackage')}")
    print(f"  {os.path.join(args.target_dir, 'LemmatizerDecoderStep.mlpackage')}")
    print(f"  {os.path.join(args.target_dir, 'lemma_vocabs.json')}")
    print(f"  {os.path.join(args.target_dir, 'lemma_dict.json')}")
    print("\nSee LemmatizerRunner.swift for the Swift-side loop that drives")
    print("these two models plus the dictionary fallback.")


if __name__ == "__main__":
    main()
