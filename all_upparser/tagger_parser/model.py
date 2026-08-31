"""Joint UPOS / XPOS / morphological-features / lemma-rule / dependency-parsing
model.

Architecture (all choices favour later Core ML conversion + on-device
efficiency over squeezing out the last 0.5% accuracy):

    word form ---> char-CNN ---\
                                 concat --> proj --> BiLSTM (encoder) --+--> UPOS head
    word (lowercased) --> emb -/                                       +--> XPOS head
                                                                        +--> FEATS head
                                                                        +--> lemma-rule head
                                                                        +--> biaffine arc scorer  --> HEAD
                                                                        +--> biaffine label scorer --> DEPREL

We use BiLSTMs rather than a self-attention transformer encoder: they are
far smaller, train fine from scratch on treebank-sized data (no pretrained
weights needed), and convert very predictably to Core ML for on-device
inference.

The biaffine arc/label scorer follows Dozat & Manning, "Deep Biaffine
Attention for Neural Dependency Parsing" (2017), simplified for clarity.
"""
import torch
import torch.nn as nn


class CharCNNEncoder(nn.Module):
    """Turns a padded [B, T, L] tensor of character ids into a [B, T, out_dim]
    word representation using parallel 1-D convolutions of different widths
    (Kim et al.-style character CNN)."""

    def __init__(self, vocab_size, char_emb_dim=32, num_filters=30,
                 kernel_sizes=(3, 4, 5), pad_id=0):
        super().__init__()
        self.embedding = nn.Embedding(vocab_size, char_emb_dim, padding_idx=pad_id)
        self.convs = nn.ModuleList([
            nn.Conv1d(char_emb_dim, num_filters, kernel_size=k, padding=k // 2)
            for k in kernel_sizes
        ])
        self.out_dim = num_filters * len(kernel_sizes)

    def forward(self, char_ids):
        # Reshape using -1 and an inline `.shape[-1]` reference (rather than
        # pre-extracting b, t, l as plain Python ints) so this stays a
        # dynamic, trace-safe op under torch.jit.trace -- important for
        # flexible-length Core ML conversion. Baking b/t/l as constants here
        # would silently pin the converted model to one fixed sentence
        # length and word length.
        x = char_ids.reshape(-1, char_ids.shape[-1])
        emb = self.embedding(x).transpose(1, 2)  # [B*T, char_emb_dim, L]
        pooled = []
        for conv in self.convs:
            c = torch.relu(conv(emb))
            p, _ = c.max(dim=2)
            pooled.append(p)
        out = torch.cat(pooled, dim=1)
        return out.reshape(char_ids.shape[0], char_ids.shape[1], self.out_dim)


class Biaffine(nn.Module):
    """Generic biaffine scorer: score(x1, x2) = x1^T W x2 (+ bias terms)."""

    def __init__(self, in1_dim, in2_dim, out_dim=1, bias1=True, bias2=True):
        super().__init__()
        self.bias1, self.bias2, self.out_dim = bias1, bias2, out_dim
        in1 = in1_dim + (1 if bias1 else 0)
        in2 = in2_dim + (1 if bias2 else 0)
        self.weight = nn.Parameter(torch.zeros(out_dim, in1, in2))
        nn.init.xavier_uniform_(self.weight)

    def forward(self, x1, x2):
        # Appending a constant "1.0" column implements the biaffine bias
        # term (x -> [x, 1], so the bias becomes a learned weight against a
        # constant). We use F.pad rather than `.new_ones(...)` + `torch.cat`
        # here specifically because coremltools has no converter for the
        # `new_ones` op -- F.pad's constant-padding lowers to an op it does
        # support, and produces an identical result.
        if self.bias1:
            x1 = nn.functional.pad(x1, (0, 1), value=1.0)
        if self.bias2:
            x2 = nn.functional.pad(x2, (0, 1), value=1.0)
        scores = torch.einsum("bxi,oij,byj->boxy", x1, self.weight, x2)
        if self.out_dim == 1:
            scores = scores.squeeze(1)
        return scores


def _mlp(in_dim, out_dim, dropout):
    return nn.Sequential(nn.Linear(in_dim, out_dim), nn.ReLU(), nn.Dropout(dropout))


class UDModel(nn.Module):
    def __init__(self, word_vocab_size, char_vocab_size, num_upos, num_xpos,
                 num_feats, num_lemma_rules, num_deprel,
                 word_emb_dim=100, char_emb_dim=32, char_num_filters=30,
                 encoder_hidden=256, encoder_layers=3, arc_mlp_dim=400,
                 label_mlp_dim=100, dropout=0.33, word_pad_id=0, char_pad_id=0):
        super().__init__()
        self.char_encoder = CharCNNEncoder(
            char_vocab_size, char_emb_dim=char_emb_dim,
            num_filters=char_num_filters, pad_id=char_pad_id,
        )
        self.word_embedding = nn.Embedding(word_vocab_size, word_emb_dim, padding_idx=word_pad_id)
        input_dim = word_emb_dim + self.char_encoder.out_dim
        self.input_proj = nn.Linear(input_dim, encoder_hidden)
        self.input_dropout = nn.Dropout(dropout)

        self.encoder = nn.LSTM(
            encoder_hidden, encoder_hidden, num_layers=encoder_layers,
            batch_first=True, bidirectional=True,
            dropout=dropout if encoder_layers > 1 else 0.0,
        )
        enc_dim = encoder_hidden * 2

        # Tagging / lemmatization heads: simple linear classifiers over the
        # contextual encoding.
        self.upos_head = nn.Linear(enc_dim, num_upos)
        self.xpos_head = nn.Linear(enc_dim, num_xpos)
        self.feats_head = nn.Linear(enc_dim, num_feats)
        self.lemma_head = nn.Linear(enc_dim, num_lemma_rules)

        # Dependency parsing heads (biaffine, Dozat & Manning 2017).
        self.arc_dep_mlp = _mlp(enc_dim, arc_mlp_dim, dropout)
        self.arc_head_mlp = _mlp(enc_dim, arc_mlp_dim, dropout)
        self.arc_biaffine = Biaffine(arc_mlp_dim, arc_mlp_dim, out_dim=1, bias1=True, bias2=False)

        self.label_dep_mlp = _mlp(enc_dim, label_mlp_dim, dropout)
        self.label_head_mlp = _mlp(enc_dim, label_mlp_dim, dropout)
        self.label_biaffine = Biaffine(label_mlp_dim, label_mlp_dim, out_dim=num_deprel,
                                        bias1=True, bias2=True)

    def forward(self, word_ids, char_ids, lengths):
        word_emb = self.word_embedding(word_ids)          # [B, T, word_emb_dim]
        char_repr = self.char_encoder(char_ids)             # [B, T, char_out_dim]
        combined = torch.cat([word_emb, char_repr], dim=-1)
        combined = self.input_dropout(torch.relu(self.input_proj(combined)))

        packed = nn.utils.rnn.pack_padded_sequence(
            combined, lengths.cpu(), batch_first=True, enforce_sorted=False
        )
        packed_out, _ = self.encoder(packed)
        enc_out, _ = nn.utils.rnn.pad_packed_sequence(packed_out, batch_first=True)

        arc_dep = self.arc_dep_mlp(enc_out)
        arc_head = self.arc_head_mlp(enc_out)
        arc_logits = self.arc_biaffine(arc_dep, arc_head)   # [B, T, T]: [b, dep, head]

        label_dep = self.label_dep_mlp(enc_out)
        label_head = self.label_head_mlp(enc_out)
        label_logits = self.label_biaffine(label_dep, label_head)  # [B, num_deprel, T, T]

        return {
            "upos": self.upos_head(enc_out),
            "xpos": self.xpos_head(enc_out),
            "feats": self.feats_head(enc_out),
            "lemma_rule": self.lemma_head(enc_out),
            "arc": arc_logits,
            "label": label_logits,
        }