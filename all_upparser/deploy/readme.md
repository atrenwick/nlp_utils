Deployment with Swift + Swift UI

To get this test pipeline to work, an Xcode project will need the following.

1. Swift files:<br>
- `AllUpUDPipeline.swift`, which contains the code defining the pipeline;<br>
- `ProgressBars.swift`, which contains the code customising and implementing progress bars;<br>
- `conllTools.swift`, which contains code that's needed to properly process CoNLL format documents,<br>
- `AllUpUDTestView.swift`, the View that actually gets shown and implements itself and the rest of the code.<br>


2. Tokeniser components:<br>
- the .mlpackage from {lang}_tokenizer_for_xcode folder ;<br>
- the `char_vocab.json` file in the same folder.<br>

3. Tagger-parser components:
- the .mlpackage from {lang}_tagger_parser_for_xcode folder;
- all 7 json files from the same folder: <br>
    `char_vocab.json`<br>
    `deprel_vocab.json`<br>
    `feats_vocab.json`<br>
    `lemma_rule_vocab.json`<br>
    `upos_vocab.json`<br>
    `word_vocab.json`<br>
    `xpos_vocab.json`<br>

Running the pipeline gives an output something like this :

<img src="/all_upparser/deploy/TaggerParser.jpg" alt="Tagger-Parser output" width="200">
<img src="/all_upparser/deploy/RulebaseLemmatiser.jpg" alt="Focus on lemmatiser output errors" width="200">

While these show that the pipeline works, we can easily see the rule-based lemmatiser simply doesn't cut the mustard:
The lemma of `je` is `moi` for some schools of thought, but not with a capital. And `suis` should be lemmatised to `suivre` 
