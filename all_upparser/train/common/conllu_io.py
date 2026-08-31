"""Minimal CoNLL-U reader.

We deliberately avoid depending on third-party CoNLL-U parsing libraries so
behaviour with multiword tokens (e.g. id "1-2") and empty nodes (e.g. id
"1.1") is fully explicit and doesn't depend on a particular library version.

CoNLL-U columns: ID, FORM, LEMMA, UPOS, XPOS, FEATS, HEAD, DEPREL, DEPS, MISC
Reference: https://universaldependencies.org/format.html
"""

FIELDS = ["id", "form", "lemma", "upos", "xpos", "feats", "head", "deprel", "deps", "misc"]


def _parse_misc(misc):
    d = {}
    if misc in ("_", "", None):
        return d
    for part in misc.split("|"):
        if "=" in part:
            k, v = part.split("=", 1)
            d[k] = v
        else:
            d[part] = True
    return d


def _parse_line(line):
    cols = line.split("\t")
    if len(cols) != 10:
        return None
    cols[-1] = cols[-1].rstrip("\n")
    tok = dict(zip(FIELDS, cols))
    tok["misc"] = _parse_misc(tok["misc"])
    return tok


def is_normal_token(tok):
    """A genuine syntactic word: has its own POS/HEAD/DEPREL annotation."""
    return tok["id"].isdigit()


def is_multiword_token(tok):
    """A surface-form span like "1-2" (e.g. French "du" = "de" + "le"). No annotation of its own."""
    return "-" in tok["id"]


def is_empty_node(tok):
    """An empty node like "1.1", used for elided predicates. Not part of raw surface text."""
    return "." in tok["id"]


def read_conllu(path):
    """Yield sentences as lists of raw token-row dicts (unfiltered: includes MWT/empty-node rows)."""
    sentence = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip():
                if sentence:
                    yield sentence
                    sentence = []
                continue
            if line.startswith("#"):
                continue
            tok = _parse_line(line)
            if tok is not None:
                sentence.append(tok)
    if sentence:
        yield sentence


def read_conllu_sentences(path):
    return list(read_conllu(path))


def normal_tokens(sentence):
    """Only the syntactic word tokens used for tagging / lemmatizing / parsing."""
    return [t for t in sentence if is_normal_token(t)]
