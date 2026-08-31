# Shim modules to preserve imports/CLI. The real implementation has been moved
# to all_upparser/train/tokenizer/; these modules re-export from the new location
# so existing imports like `from tokenizer.model import CharTokenizer` continue
# to work when this package layout is used.

from all_upparser.train.tokenizer.data import *  # noqa: F401,F403
