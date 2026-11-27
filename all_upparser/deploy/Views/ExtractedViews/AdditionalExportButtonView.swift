//
//  AdditionalExportButton.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//
import SwiftUI

struct AdditionalExportButtonView: View{
    @Environment(AppModel.self) internal var model
    @Binding var additionalExportFormat: ExportFormat
    @Binding var alertMessage: String?
    let run: RunOutput
    var body: some View{
        Button {
            do {
                let runOutput = try additionalExportRunner(
                    run: run,
                    additionalExportFormat: additionalExportFormat,
                    processingStatus: model.myConfig.progressConfig.processingStatus
                )
                if let hasURL = runOutput.runMetas.savedURL{
                    model.runOutputFileList.append(
                        OutputFileListHelper(
                            id: UUID(),
                            runID: runOutput.runMetas.runID,
                            url: hasURL
                        )
                    )
                }
                model.allRunOutputs.append(runOutput)
            } catch {
                switch error {
                    case let exportError as PipelineError.ExportError:
                        alertMessage = exportError.errorDescription
                    default:
                        alertMessage = error.localizedDescription
                }
            }
        } label: {
            Text("Export")
        }
        .tint(.green)
        .buttonStyle(.borderedProminent)
    }
    
}

extension AdditionalExportButtonView{
    func additionalExportRunner(
        run: RunOutput,
        additionalExportFormat: ExportFormat,
        processingStatus: ProcessingStatus
    ) throws -> RunOutput {
        @Bindable var model = model
        var newRunNumber: Int = model.runNum
        newRunNumber += 1
        model.runNum = newRunNumber
        
        let exportContent = GeneralOutputMakingWorkflow.makeExportContent(
            headers: run.runMetas.safeHeaderAttribs,
            sents: run.runData.sents,
            exportFormat: additionalExportFormat,
            includeConllSentText: run.runMetas.includeConllSentText,
            processingStatus: processingStatus
        )
        guard !exportContent.isEmpty else {
            print("throw @213")
            throw PipelineError.ExportError.makeExportContentError
        }
        let runData = RunData(
            runID: run.runID,
            sents: run.runData.sents,
            exportContent: exportContent
        )
        let additionalExportParams = AdditionalExportParams(exportFormat: additionalExportFormat, includeConllSentText: run.runMetas.includeConllSentText
        )
        let pipelineRequestForAdditional = PipelineBuildRequest(
            languageCode: Language(rawValue: run.runMetas.lang) ?? Language.FR,
            base: ModelArchitecture(rawValue: run.runMetas.safeHeaderAttribs.modelArchitecture) ?? ModelArchitecture.cnnBiLSTM,
            treebank: Language.Treebank(rawValue: run.runMetas.treebank) ?? Language.Treebank.frTB1
        )
        let runMetas = WritingWorkflow.saveFileToChosenLocation(
            myConfig: model.myConfig,
            exportContent: exportContent,
            pipelineRequest: pipelineRequestForAdditional,
            runID: run.runID,
            processingStatus: model.myConfig.progressConfig.processingStatus,
            additional: additionalExportParams
        )
        let runOutput = RunOutput(num: newRunNumber, runID: run.runID, runData: runData, runMetas: runMetas)
        return runOutput
    }
    
    
    
}
