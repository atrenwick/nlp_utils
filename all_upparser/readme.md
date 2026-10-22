An all up parser

What I wanted: a button in an iOS app to run a pipeline to sentences, tokenise, POS tag, lemmatise, add morphological features, and add syntactic dependencies to text, then export to file.
Why do all this ? To learn a bit of Swift + SwiftUI while putting a bit of Py into the mix to train some models to do all the processing on-device.


<p>
The all-up parser taking a user-refined tokenisation of text (below left) or a file (below right), then parsing and exporting to XML with POS tags, lemmas, morphological feats and dependency annotations, all predicted on-device.
</p>
<p align="center">
  <img src="./deploy/TaggerTokenisation.gif" alt="Parser demo from customised sentences + tokenisation" width="360" />
   &nbsp;&nbsp;
  <img src="./deploy/Tagger.gif" alt="Parser demo from file" width="360" />
</p> 




  
