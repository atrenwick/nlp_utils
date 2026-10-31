//
//  PipelineErrors.swift
//  Tagger
//
//  Created by Adam on 28/10/2026.
//

import Foundation

enum PipelineError: LocalizedError{
    
    // MARK: - Errors
    enum TokPieceError: Error, LocalizedError {
        case vocabUnreadable(URL)
        case missingSpecialToken(String)
        case missingSetting(String)
        case tooManyWords(have: Int, limit: Int)
        case tooManySubwords(have: Int, limit: Int)
        case tokenizerTryError
        case wordPieceTokenizerError
        case other
        var errorDescription: String? {
            switch self {
            case .other:
                return "Other type of error"
            case .wordPieceTokenizerError:
                return "error encoding after tokenizer made"
            case .tokenizerTryError:
                return "Try failed in test funct"
            case .vocabUnreadable(let url):
                return "Couldn't read the vocabulary file at \(url.lastPathComponent)"
            case .missingSpecialToken(let name):
                return "Special token \(name) isn't in the vocabulary"
            case .missingSetting(let name):
                return "tokenizer_config.json has no \"\(name)\"; pass it explicitly when creating the tokenizer"
            case .tooManyWords(let have, let limit):
                return "Sentence has \(have) words; the model accepts at most \(limit)"
            case .tooManySubwords(let have, let limit):
                return "Sentence needs \(have) subword tokens; the model accepts at most \(limit)"
            }
        }
    }

    enum SentencePieceTokenizerError: Error, LocalizedError {
        case fileUnreadable(URL)
        case unsupportedModel(String)
        case missingSpecialToken(String)
        case tooLong(subwords: Int, seqLen: Int, slots: Int, maxWords: Int)

        var errorDescription: String? {
            switch self {
            case .fileUnreadable(let url):
                return "Could not read tokenizer file at \(url.lastPathComponent)."
            case .unsupportedModel(let type):
                return "tokenizer.json holds a \(type) model; this tokenizer only supports Unigram (CamemBERT)."
            case .missingSpecialToken(let token):
                return "Special token \(token) not found in the tokenizer vocabulary."
            case .tooLong(let subwords, let seqLen, let slots, let maxWords):
                return "Sentence needs \(subwords) subwords (limit \(seqLen)) and \(slots) word slots "
                     + "(limit \(maxWords)); split or truncate it before encoding."
            }
        }
    }
    // errors in config before calling loader
    enum ConfigurationError: LocalizedError {
        case architectureConflict
        case badTempTokens
        case invalidLevel(Int)
        case invalidModelInputs(String)
        case languageMethodConflict(language: Language)
        case notReadyToSendToRunner
        case inputFileFormatChoiceError
        case resourceMissing(String)
        
        var errorDescription: String? {
            switch self{
            case .architectureConflict:
                return "conflict between architecture and available models"
            case .badTempTokens:
                return "Error makiing hashable sentence from temp tokens"
            case .inputFileFormatChoiceError:
                return "Not an XML format"
            case .invalidLevel(let level):
                return "Invalid pipeline level \(level): must be between 1 and 5."
            case .invalidModelInputs(let detail):
                return "Unexpected model inputs: \(detail)"
            case .languageMethodConflict(let language):
                return "Language \(language.rawValue) cannot be used with naive tokenisation"
            case .notReadyToSendToRunner:
                return "Not ready to send to from loader class to runner class"
            case .resourceMissing(let name):
                return "Missing resource: \(name)"
                
            }
        }
    }
    // errors when loader tries to load
    enum LoadingError: LocalizedError{
        case configFileLoadError(name: String)
        case fileLoadError
        case fileNotInBundle
        case modelLoadFailed(Error)
        case packageLoadFailed(String)
        
        var errorDescription: String? {
            switch self{
            case .configFileLoadError(let filename):
                return "Failed to load file config file \(filename)"
            case .fileLoadError:
                return "Failed to load file"
            case .fileNotInBundle:
                return "File not in bundle"
            case .modelLoadFailed(let error):
                return "Couldn't load the model: \(error.localizedDescription)"
            case .packageLoadFailed(let name):
                return "Failed to load model from package \(name)"
            }
        }
    }
    
    // errors getting stuff for the now loaded pipeline to process
    enum IngestionError: LocalizedError{
        case conllParsingError(line: String, filename:String)
        case conllLineIdentificationError
        case conllChunkToLineError
        case emptyInput
        case makeConllLinesFromURLError
        case noSentencesLoaded
        case parserCreationError(file: URL)
        case retokenisationError
        case tokenizationFail(String)
        case utf8DecodeError
        case xmlParserFailure(line: Int, reason: String)
        case readFromSandboxError

        var errorDescription: String? {
            switch self{
            case .conllParsingError(let lineNumber, let filename):
                return "Error parsing conll lines : 10 fields not found in file \(filename) line \(lineNumber)"
            case .conllLineIdentificationError:
                return "Error getting finding sentence chunks in conll input"
            case .conllChunkToLineError:
                return "Error in conllChunkToLineError function"
            case .emptyInput:
                return "There are no words to annotate"
            case .utf8DecodeError:
                return "Failed to decode as UTF-8"
            case .xmlParserFailure:
                return "Unknown XML parsing error with XML parser + delegate"
            case .retokenisationError:
                return "Error retokenising: no sentences found"
            case .tokenizationFail(let message):
                return "Tokenisation failed :: \(message)"
            case .makeConllLinesFromURLError:
                return "Error in makeConllLinesFromURL function"
            case .noSentencesLoaded:
                return "No sentences found when switching on inputFileTYpe"
            case .parserCreationError(let file):
                return "Couldn't create XML parser from \(file.lastPathComponent)"
            case .readFromSandboxError:
                return "Error reading the file from the sandbox"
                
            }
        }
    }
    // errors when pipeline tries to turn A into B
    enum ProcessingError: LocalizedError{
        case lemmatizationFailed(String)
        case noRunOutput
        case predictionFailed(Error)
        case predictionFailedAtLogits(String)
        var errorDescription: String? {
            switch self{
            case .predictionFailed(let error):
                return "The model failed to run: \(error.localizedDescription)"
            case .predictionFailedAtLogits(let message):
                return message
            case .noRunOutput:
                return "No run output to return"
            case .lemmatizationFailed(let msg):
                return "Lemmatization failed: \(msg)"
            }
        }
    }
    // errors when tryign to save what pipeline returned
    enum ExportError: LocalizedError{
        case fileSaveError(filename: String)
        case makeExportContentError
        case outputFolderCreationError
        
        var errorDescription: String? {
            switch self{
            case .fileSaveError(let filename):
                return "Failed to save to file \(filename)"
            case .makeExportContentError:
                return "Error in makeExportContent function"
            case .outputFolderCreationError:
                return "Can't create the output folder in sandbox"
            }
        }
    }
    
    enum GenericError: LocalizedError{
        case missingResource(String)
        case missingURL
        case unexpectedOutput(String)
        
        var errorDescription: String? {
            switch self{
            case .missingResource(let name):
                return "Missing bundled resource: \(name). Did you add it to the app target?"
            case .missingURL:
                return "No URL provided"
            case .unexpectedOutput(let detail):
                return "Unexpected model output: \(detail)"
            }
        }
    }
}
