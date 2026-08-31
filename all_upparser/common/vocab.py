"""Vocabulary utilities shared by the tokenizer and tagger/parser models."""
import json
from collections import Counter


class Vocab:
    def __init__(self, pad="<pad>", unk="<unk>", specials=None):
        self.pad = pad
        self.unk = unk
        specials = specials or []
        self.itos = list(dict.fromkeys([pad, unk] + list(specials)))
        self.stoi = {s: i for i, s in enumerate(self.itos)}

    def add(self, token):
        if token not in self.stoi:
            self.stoi[token] = len(self.itos)
            self.itos.append(token)
        return self.stoi[token]

    def encode(self, token):
        return self.stoi.get(token, self.stoi[self.unk])

    def __len__(self):
        return len(self.itos)

    @property
    def pad_id(self):
        return self.stoi[self.pad]

    @property
    def unk_id(self):
        return self.stoi[self.unk]

    def build_from_counter(self, counter, min_freq=1, max_size=None):
        items = sorted(counter.items(), key=lambda x: (-x[1], x[0]))
        n = 0
        for tok, freq in items:
            if freq < min_freq:
                continue
            self.add(tok)
            n += 1
            if max_size and n >= max_size:
                break

    def build_from_tokens(self, tokens, min_freq=1, max_size=None):
        self.build_from_counter(Counter(tokens), min_freq=min_freq, max_size=max_size)

    def to_json(self):
        return {"itos": self.itos, "pad": self.pad, "unk": self.unk}

    @classmethod
    def from_json(cls, data):
        v = cls(pad=data["pad"], unk=data["unk"])
        v.itos = data["itos"]
        v.stoi = {s: i for i, s in enumerate(v.itos)}
        return v

    def save(self, path):
        with open(path, "w", encoding="utf-8") as f:
            json.dump(self.to_json(), f, ensure_ascii=False, indent=2)

    @classmethod
    def load(cls, path):
        with open(path, "r", encoding="utf-8") as f:
            return cls.from_json(json.load(f))
