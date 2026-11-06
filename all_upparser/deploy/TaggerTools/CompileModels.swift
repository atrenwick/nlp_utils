#!/usr/bin/env swift
//  CompileModels.swift
//  Tagger

//
//  Compiles Core ML models (.mlpackage / .mlmodel) into .mlmodelc folders on your Mac and won't run on iOS.
//  calling from from Terminal:
//
//      swift Tools/CompileModels.swift                       # ./Models  ->  ./CompiledModels
//      swift Tools/CompileModels.swift --src ~/MLModels --out ~/MLCompiled
//      swift Tools/CompileModels.swift --target 17.0         # deployment target (see note below)
//      swift Tools/CompileModels.swift --force               # recompile everything
//      swift Tools/CompileModels.swift Models/Tagger.mlpackage Models/Parser.mlpackage
//
//  Models whose source files haven't changed since the last successful compile are skipped.
//
//  Notes::
//  `--target 12.34` :: if omitted, most recent OS in Xcode
//  --platform defaults to "ios", can be "macos" for a native Mac app

import Foundation

let fm = FileManager.default

// MARK: - Small helpers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(2)
}

func nextValue(after flag: String, _ args: inout [String]) -> String {
    guard !args.isEmpty else { fail("\(flag) needs a value") }
    return args.removeFirst()
}

func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL
}

func readable(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

/// Newest modification time of the item itself or anything inside it.
func newestModification(of url: URL) -> Date {
    let keys: [URLResourceKey] = [.contentModificationDateKey]
    var newest = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
    if let e = fm.enumerator(at: url, includingPropertiesForKeys: keys) {
        for case let f as URL in e {
            if let d = (try? f.resourceValues(forKeys: Set(keys)))?.contentModificationDate, d > newest {
                newest = d
            }
        }
    }
    return newest
}

/// Total size in bytes of a file, or of every regular file inside a folder.
func totalSize(of url: URL) -> Int64 {
    let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
    func size(_ u: URL) -> Int64 {
        guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { return 0 }
        return Int64(v.fileSize ?? 0)
    }
    var total = size(url)
    if let e = fm.enumerator(at: url, includingPropertiesForKeys: keys) {
        for case let f as URL in e { total += size(f) }
    }
    return total
}

/// Runs a command through xcrun, returning its exit status and combined output.
func runXcrun(_ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { return (127, "could not launch xcrun: \(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()   // read before waiting, so a full pipe can't stall it
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

// MARK: - Arguments

var srcDir = "Models"
var outDir = "CompiledModels"
var force = false
var target: String? = nil
var platform = "ios"
var explicitInputs: [String] = []

var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--src":      srcDir = nextValue(after: a, &args)
    case "--out":      outDir = nextValue(after: a, &args)
    case "--target":   target = nextValue(after: a, &args)
    case "--platform": platform = nextValue(after: a, &args)
    case "--force":    force = true
    case "-h", "--help":
        print("usage: CompileModels.swift [--src DIR] [--out DIR] [--target 17.0] [--platform ios|macos] [--force] [model ...]")
        exit(0)
    default:
        if a.hasPrefix("--") { fail("unknown option \(a)") }
        explicitInputs.append(a)
    }
}

let outRoot = fileURL(outDir)

// MARK: - Find the models to compile

func findModels(under root: URL) -> [URL] {
    guard let e = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
        return []
    }
    var found: [URL] = []
    for case let url as URL in e {
        let ext = url.pathExtension
        if ext == "mlpackage" || ext == "mlmodel" {
            // don't pick up anything that lives inside the output folder
            if !url.path.hasPrefix(outRoot.path + "/") { found.append(url) }
            e.skipDescendants()
        }
    }
    return found
}

var models: [URL]
if explicitInputs.isEmpty {
    let root = fileURL(srcDir)
    guard fm.fileExists(atPath: root.path) else { fail("source folder \(root.path) does not exist (use --src)") }
    models = findModels(under: root)
} else {
    models = explicitInputs.map(fileURL)
    for m in models where !fm.fileExists(atPath: m.path) { fail("\(m.path) does not exist") }
}
models.sort { $0.lastPathComponent < $1.lastPathComponent }

if models.isEmpty {
    print("no .mlpackage or .mlmodel files found")
    exit(0)
}

// two models with the same name would write to the same output
let names = models.map { $0.deletingPathExtension().lastPathComponent }
let duplicates = Dictionary(grouping: names, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
if !duplicates.isEmpty { fail("more than one model is named: \(duplicates.joined(separator: ", "))") }

do { try fm.createDirectory(at: outRoot, withIntermediateDirectories: true) }
catch { fail("could not create \(outRoot.path): \(error)") }

// MARK: - Compile

enum Outcome { case compiled, upToDate, failed(String) }

/// Records what the last successful compile was made from. Re-compiles when the source files,
/// --target or --platform change. Kept beside the output, not inside the .mlmodelc.
func stampText(for model: URL) -> String {
    let ms = Int(newestModification(of: model).timeIntervalSince1970 * 1000)
    return "\(ms)|\(target ?? "-")|\(platform)"
}

func compile(_ model: URL) -> Outcome {
    let name = model.deletingPathExtension().lastPathComponent
    let finalURL = outRoot.appendingPathComponent("\(name).mlmodelc")
    let stampURL = outRoot.appendingPathComponent(".\(name).stamp")
    let stamp = stampText(for: model)

    if !force,
       fm.fileExists(atPath: finalURL.path),
       (try? String(contentsOf: stampURL, encoding: .utf8)) == stamp {
        return .upToDate
    }

    // build in a scratch folder so a failed compile never destroys the previous good output
    let scratch = outRoot.appendingPathComponent(".building-\(name)")
    try? fm.removeItem(at: scratch)
    do { try fm.createDirectory(at: scratch, withIntermediateDirectories: true) }
    catch { return .failed("could not create scratch folder: \(error)") }
    defer { try? fm.removeItem(at: scratch) }

    var arguments = ["coremlcompiler", "compile", model.path, scratch.path]
    if let target { arguments += ["--deployment-target", target] }
    arguments += ["--platform", platform]

    let result = runXcrun(arguments)
    guard result.status == 0 else {
        var message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.contains("unable to find utility") {
            message += "\n(Xcode's tools aren't selected. Try: sudo xcode-select -s /Applications/Xcode.app)"
        }
        return .failed(message)
    }

    let built = scratch.appendingPathComponent("\(name).mlmodelc")
    guard fm.fileExists(atPath: built.path) else {
        return .failed("the compiler finished but \(name).mlmodelc was not produced\n\(result.output)")
    }

    do {
        try? fm.removeItem(at: finalURL)
        try fm.moveItem(at: built, to: finalURL)
        try stamp.write(to: stampURL, atomically: true, encoding: .utf8)
    } catch {
        return .failed("could not install the compiled model: \(error)")
    }
    return .compiled
}

var compiledCount = 0, skippedCount = 0, failedCount = 0
print("compiling into \(outRoot.path)  (platform: \(platform), target: \(target ?? "compiler default"))\n")

for model in models {
    let name = model.deletingPathExtension().lastPathComponent
    switch compile(model) {
    case .compiled:
        compiledCount += 1
        let out = outRoot.appendingPathComponent("\(name).mlmodelc")
        print("  compiled    \(name)   \(readable(totalSize(of: model))) -> \(readable(totalSize(of: out)))")
    case .upToDate:
        skippedCount += 1
        print("  up to date  \(name)")
    case .failed(let message):
        failedCount += 1
        print("  FAILED      \(name)\n      " + message.replacingOccurrences(of: "\n", with: "\n      "))
    }
}

print("\n\(compiledCount) compiled, \(skippedCount) up to date, \(failedCount) failed")
if compiledCount + skippedCount > 0 {
    print("Copy the .mlmodelc folders from \(outRoot.path) to the app's Documents folder (e.g. DevModels/) using Finder.")
}
exit(failedCount == 0 ? 0 : 1)
