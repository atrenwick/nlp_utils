Deployment with Swift + Swift UI

To get this test pipeline to work, an Xcode project will need the following.

1. Swift files
-`AllUpUDPipeline.swift`, which contains the code defining the pipeline;\n
-`AllUpUDTestView.swift`, which defines the View that actually gets shown and implements the code laid out in `AllUpUDPipeline.swift`;\n
-`ProgressBars.swift`, which contains the code customising and implementing progress bars;\n
-`conllTools.swift`, which contains code that's needed to properly process CoNLL format documents.\n

2. Tokeniser components:
- the .mlpackage from {lang}_tokenizer_for_xcode folder ;\n
- the `char_vocab.json` file in the same folder.\n

3. Tagger-parser components:
- the .mlpackage from {lang}_tagger_parser_for_xcode folder;\n
- all 7 json files from the same folder, which define:\n
    -- `char_vocab.json`\n
    -- `deprel_vocab.json`\n
    -- `feats_vocab.json`\n
    -- `lemma_rule_vocab.json`\n
    -- `upos_vocab.json`\n
    -- `word_vocab.json`\n
    -- `xpos_vocab.json`\n

