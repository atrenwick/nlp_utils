Deployment with Swift + Swift UI

To get this test pipeline to work, an Xcode project will need the following.

1. Swift files
--`AllUpUDPipeline.swift`, which contains the code defining the pipeline;
--`AllUpUDTestView.swift`, which defines the View that actually gets shown and implements the code laid out in `AllUpUDPipeline.swift`;
--`ProgressBars.swift`, which contains the code customising and implementing progress bars;
--`conllTools.swift`, which contains code that's needed to properly process CoNLL format documents.

2. Tokeniser components:
-- the .mlpackage from {lang}_tokenizer_for_xcode folder ;
-- the `char_vocab.json` file in the same folder.

3. Tagger-parser components:
- the .mlpackage from {lang}_tagger_parser_for_xcode folder;
- all 7 json files from the same folder, which define:
    -- `char_vocab.json`
    -- `deprel_vocab.json`
    -- `feats_vocab.json`
    -- `lemma_rule_vocab.json`
    -- `upos_vocab.json`
    -- `word_vocab.json`
    -- `xpos_vocab.json`

