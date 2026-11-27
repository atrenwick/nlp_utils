//
//  ToolbarSaveButton.swift
//  Tagger
//
//  Created by Adam on 27/11/2026.
//
import SwiftUI

struct ToolbarSaveButtonView: View{
    let run: RunOutput
    @Binding var alertMessage: String?
    var body: some View{
        Button{
            do {
                if let savedURL = try PipelineServices.ResultStorageManager.saveRun(run){
                    print("Saved to \(savedURL)")}
            } catch {
                switch error {
                    case let fileSaveError as PipelineError.ExportError:
                        alertMessage = fileSaveError.errorDescription
                    default:
                        alertMessage = error.localizedDescription
                }
            }
        } label: {
            Text("Save")
        }
    }
}
