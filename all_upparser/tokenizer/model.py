"""Character-level BiLSTM tokenizer / sentence-segmenter.

Small and fast by design: this runs as the first stage on-device, over raw
input text, before the tagger/parser model ever sees a single token.
"""
import torch
import torch.nn as nn


class CharTokenizer(nn.Module):
    def __init__(self, vocab_size, char_emb_dim=64, hidden_size=128, num_layers=2,
                 num_labels=4, dropout=0.3, pad_id=0):
        super().__init__()
        self.embedding = nn.Embedding(vocab_size, char_emb_dim, padding_idx=pad_id)
        self.lstm = nn.LSTM(
            char_emb_dim, hidden_size, num_layers=num_layers,
            batch_first=True, bidirectional=True,
            dropout=dropout if num_layers > 1 else 0.0,
        )
        self.dropout = nn.Dropout(dropout)
        self.classifier = nn.Linear(hidden_size * 2, num_labels)

    def forward(self, char_ids, lengths):
        emb = self.embedding(char_ids)
        packed = nn.utils.rnn.pack_padded_sequence(
            emb, lengths.cpu(), batch_first=True, enforce_sorted=False
        )
        packed_out, _ = self.lstm(packed)
        out, _ = nn.utils.rnn.pad_packed_sequence(packed_out, batch_first=True)
        out = self.dropout(out)
        return self.classifier(out)
