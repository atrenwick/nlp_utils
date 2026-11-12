//
//  XMLparsingView.swift
//  Tagger
//
//  Created by Adam on 18/09/2026.
//

import SwiftUI
//
//struct XMLparsingView: View {
//    var body: some View {
//        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
//    }
//}

//#Preview {
//    XMLparsingView()
//}


//    @State var newsArticles: [CCNewsArticle] = []
//    var ccSents: [String]  {
//        var result: [String] = []
//        for ccArt in newsArticles {
//            let articleText = ccArt.allText
//            for sent in articleText.components(separatedBy: ". ") {
//                let normalized = sent.replacingOccurrences(of: "\u{2019}", with: "'")
//                let trimmed = normalized.trimmingCharacters(in: .whitespaces)
//                if !trimmed.isEmpty {
//                    result.append(trimmed)
//                }
//            }
//        }
//        return result
//    }


//////MARK: structures
////typealias StructureMap = [Int: CCNewsArticle]
////
//struct CCNewsArticle : Identifiable, Codable {
//    //Think of it as: case <what my property is called> = "<what the JSON actually says>".
//
//    enum CodingKeys: String, CodingKey, Codable {
//        case url = "url"
//        case allText =  "txt"
//        case title = "title"
//        case author = "author"
//        case site = "site"
//        case respURL = "resp_url"
//        case publication = "publi"
//        case warcPath = "warc_path"
//        case crawlDate = "crawl_date"
//        case month = "month"
//        case day = "day"
//    }
//
//    var id = UUID()
//    let url: String
//    let allText: String
//    let title: String
//    let author: String?
//    let site: String?
//    let respURL: String?
//    let publication: String?
//    let warcPath: String?
//    let crawlDate: String?
//    let month: String?
//    let day: String?
//
//}
//struct CCNewsArticleContainerStructure: Identifiable {
//    let id: Int          // the original key
//    let value: CCNewsArticle
//}
//
////
//


//case .success(let urls):
//    guard let url = urls.first else { return }
//    guard url.startAccessingSecurityScopedResource() else { return }
//    defer { url.stopAccessingSecurityScopedResource() }
//
//    do {
//        myConfig.exportConfig.targetFolderURL = url // send url to config for this run's output
//        outputDirBookmark = try url.bookmarkData(   // send bookmark to
//            options: [],                      // on iOS, no .withSecurityScope option
//            includingResourceValuesForKeys: nil,
//            relativeTo: nil
//        )
//    } catch {
//        print("Bookmark error: \(error)")
//    }
//


//func save(_ data: Data, as name: String) throws {
//    guard let dir = resolveOutputDir() else { throw SaveError.noFolder }
//    guard dir.startAccessingSecurityScopedResource() else { throw SaveError.noAccess }
//    defer { dir.stopAccessingSecurityScopedResource() }
//
//    try data.write(to: dir.appendingPathComponent(name))
//}
//





