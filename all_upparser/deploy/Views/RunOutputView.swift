//
//  RunOutputView.swift
//  Tagger
//
//  Created by Adam on 11/09/2026.
//
import SwiftUI

// overview list of runs == parent
struct RunOutputView: View {
    @Environment(AppModel.self) private var model
    @State var showImporter: Bool = false
    @State var runsToCompare: [RunOutput] = []
    @State var alertMessage: String?
    var body: some View {
        @Bindable var model = model
        NavigationStack{
            VStack{
                if model.allRunOutputs.count == 0 {
                    Text("No previous runs for this session\nTo load saved runs, use Load")
                } else {
                    Form{
                        ForEach($model.allRunOutputs){$run in
                            NavigationLink {
                                RunOutputDetailView( run: $run)
                            } label: {
                                Text(makeRunLabel(run: run, num: run.num))
                                    .foregroundStyle(
                                        (runsToCompare.map {$0.runID} ).contains(run.runID) ? .green : .orange)
                            }
                            .contentShape(Rectangle())
                            .swipeActions(edge: .leading){
                                Button(){
                                    addRemoveForComparison(run: run)
                                } label: {
                                    Label("Compare", systemImage: "cat")
                                }
                            }.contentShape(Rectangle())
                                .swipeActions(edge: .trailing){
                                    Button(role: .destructive){
                                        deleteRun(runID: run.runID)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } // end of for each
                        }
                    Section{
                        NavigationLink {
                            TaggingComparisonView(runPair: runsToCompare)
                        } label: {
                            Text("Tagging comp view \(runsToCompare.count)")
                        }
                    }
                }
                }
            }
            .toolbar{  // toolbar insidethe navstack and the sheet its action button will call
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Text("Load")
                    }
                }
            }
            .alert("Error !",
                   isPresented: Binding(
                    get: {alertMessage != nil},
                    set: {if !$0 {alertMessage = nil} } )
            ) { Button("OK", role: .cancel) { }
            } message: { Text(alertMessage ?? "") }
                .sheet(isPresented: $showImporter) {
                    RunSelectorView { selectedURL in
                        do {
                            let data = try Data(contentsOf: selectedURL)
                            let loadedResult = try JSONDecoder().decode(RunOutput.self, from: data)
                            model.allRunOutputs.append(loadedResult)
                        } catch {
                            print("Failed to decode: \(error)")
                        }
                    }
                }
        }
    }

}


extension RunOutputView {
    func makeRunLabel(run: RunOutput, num: Int) -> String{
         "Run \(num + 1): \(run.runMetas.sourceFileName) | \(run.runMetas.lang) | \(run.runMetas.safeHeaderAttribs.modelArchitecture) | \(run.runMetas.treebank) | \(run.runMetas.exportFormat)"
    }

    /// func to take an already evaluated runID and then do a delete on it, to avoid simultaneous access attempts from getID and deleteItem
    func deleteRun(runID: String){ model.allRunOutputs.removeAll {$0.runID == runID} }
    // add a leading edge swipe to set as run1, run2
    func addRemoveForComparison(run: RunOutput) {
        var existingIDs: [String] = []
        for run in runsToCompare{ existingIDs.append(run.runID) }
        if  existingIDs.contains(run.runID){
            runsToCompare.removeAll {$0.runID == run.runID}
        } else {
            if runsToCompare.count == 2{
                alertMessage = "2 items already present"
            } else {
                runsToCompare.append(run)
            }
        }
    }

    
}
