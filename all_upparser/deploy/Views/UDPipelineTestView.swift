//
//  UDTestView.swift
//
import SwiftUI



//#Preview {
//    TestView()
//}

//enum AppLaunchMode {
//    case normal
//    case portfolio
//}


//You can trigger it from the UI test using a launch argument.
/*let app = XCUIApplication()

app.launchArguments = [
    "PORTFOLIO_MODE"
]

app.launch()
*/

//Then inside your app:
//
//let isPortfolioMode =
//    ProcessInfo.processInfo.arguments.contains("PORTFOLIO_MODE")
//

//You can inject this into your dependency setup.


/*
 @main
struct MyApp: App {

    private let environment: AppEnvironment

    init() {
        if ProcessInfo.processInfo.arguments.contains("PORTFOLIO_MODE") {
            environment = .portfolio
        } else {
            environment = .production
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(environment: environment)
        }
    }
}
*/

//Now your UI tests can reliably get into interesting states.

//---

//# 3. Make a portfolio environment

//I'd go slightly further than a boolean.

//Something like:
//
//
//enum AppEnvironment {
//    case production
//    case portfolio
//    case preview
//}
//
////and
//extension AppEnvironment {
//
//    var dataProvider: DataProvider {
//        switch self {
//        case .production:
//            RealDataProvider()
//
//        case .portfolio:
//            PortfolioDataProvider()
//
//        case .preview:
//            PreviewDataProvider()
//        }
//    }
//}


//This becomes **extremely useful**.
//Your portfolio doesn't need to depend on:
//---

//# 4. Give the portfolio environment deliberately good data
//
//This is where you can make the screenshots *much* better.
//
//Suppose your app normally shows:
//
//```text
//No data yet
//```
//
//when launched fresh.
//
//That's terrible for a portfolio.
//
//Your portfolio environment might contain:
//
//```text
//PortfolioDataProvider
//
//User:
//    Alex
//
//Items:
//    14 carefully selected examples
//
//ML examples:
//    3 interesting cases
//
//History:
//    2 weeks of activity
//```

//So when the app launches in portfolio mode:
//
//**Boom.**
//
//It looks like a mature, populated application.
//
//This is essentially the same philosophy as SwiftUI previews: provide a known model state that makes the UI interesting.
//
//---
//
//# 5. Then create your first demo
//
//I'd make one file: `MyAppUITests/DemoTests.swift`


//import XCTest
//
//final class DemoTests: XCTestCase {
//    func testPortfolioDemo() throws {
//        let app = XCUIApplication()
//        app.launchArguments = [
//            "PORTFOLIO_MODE"
//        ]
//        app.launch()
//        capture("01-home")
//        app.buttons["New Analysis"].tap()
//        capture("02-input")
//        app.buttons["Analyze"].tap()
//        let result = app.staticTexts["Analysis complete"]
//        XCTAssertTrue(result.waitForExistence(timeout: 10))
//        capture("03-result")
//    }
//}


//Notice something important:
//
//These are already becoming **real tests**.
//
//You didn't set out to write tests.
//
//You set out to make a portfolio.
//
//But you've accidentally created a useful test:
//
//> Launch → New Analysis → Analyze → result appears.
//
//That's exactly the kind of UI flow Apple recommends UI tests for. ([Apple Developer][3])

//---

//# 6. Make `capture()` your own tiny abstraction

//I'd create: MyAppUITests/Screenshots.swift`
//
//import XCTest
//
//func capture(
//    _ name: String,
//    file: StaticString = #filePath,
//    line: UInt = #line
//) {
//    let screenshot = XCUIScreen.main.screenshot()
//
//    let attachment = XCTAttachment(
//        screenshot: screenshot
//    )
//
//    attachment.name = name
//    attachment.lifetime = .keepAlways
//
//    XCTContext.runActivity(
//        named: "Screenshot: \(name)"
//    ) { activity in
//        activity.add(attachment)
//    }
//}


//This uses Apple's native screenshot mechanism rather than trying to hack the simulator itself. `XCUIScreen.main.screenshot()` captures the current screen state, and screenshots can be attached to XCTest activities. ([Apple Developer][1])
//
//**However:** for the first implementation I'd actually use Fastlane Snapshot to get the PNGs onto disk conveniently, rather than building our own attachment-extraction machinery.
//
//That's what Snapshot is good at.

//---
//
//# 7. Add Fastlane Snapshot

//Your `fastlane/Snapfile` could be tiny:

//```ruby
//scheme("MyAppUITests")
//
//devices([
//  "iPhone 17 Pro"
//])
//
//languages([
//  "en-US"
//])
//
//launch_arguments([
//  "PORTFOLIO_MODE"
//])
//
//output_directory("./Portfolio/screenshots")
//
//clear_previous_screenshots(true)
//
//override_status_bar(true)
//```
//
//Then:
//
//```bash
//fastlane snapshot
//```
//
//Fastlane drives your UI tests and captures the screenshots; it can also configure simulator devices, launch arguments, output directories, and status-bar handling. ([docs.fastlane.tools][2])

//You don't need six iPhones and twenty languages.
//
//**One simulator.**
//
//For a developer portfolio, consistency matters much more than App Store compliance.


//# 8. Give screenshots semantic names
//
//Don't let the screenshot filenames become:
//
//```text
//IMG_1234.png
//IMG_1235.png
//IMG_1236.png
//```
//
//Instead:
//
//```text
//01-home.png
//02-create-analysis.png
//03-analysis-result.png
//04-history.png
//```

//Even better, put the meaning in your portfolio metadata.
//
//`Portfolio/app.yml`:
//
//```yaml
//name: My App
//
//tagline: >
//  An on-device ML app that turns X into Y.
//
//platform: iOS
//
//technologies:
//  - Swift
//  - SwiftUI
//  - Core ML
//
//status: Personal project
//
//github: https://github.com/you/MyApp
//
//hero:
//  screenshot: 01-home.png
//  video: demo.mp4
//
//screenshots:
//  - file: 01-home.png
//    title: The home screen
//    description: >
//      The main dashboard gives an overview of recent activity.
//
//  - file: 02-create-analysis.png
//    title: Create an analysis
//    description: >
//      Users provide an input and start an on-device analysis.
//
//  - file: 03-analysis-result.png
//    title: On-device ML
//    description: >
//      The model processes the input locally and presents the result.
//```

//---
//
//# 9. The README becomes automatically generated-ish
//
//Your actual repository README can be much better too.
//
//Something like:
//
//```markdown
//# My App
//
//> An on-device ML app that turns X into Y.
//
//[Watch the demo](...)
//
//![Home](Portfolio/screenshots/01-home.png)
//
//## What is it?
//
//...
//
//## Why I built it
//
//...
//
//## Technical highlights
//
//- SwiftUI
//- Core ML
//- ...
//```

//You can manually write the prose, But the screenshots are generated.
//
//---
//
//# 10. Then make the video
//
//I'd treat this as the second phase rather than blocking the screenshot system on it.
//The desired pipeline is:
//
//```text
//DemoTests.swift
//       │
//       ├──────────→ screenshots
//       │
//       └──────────→ video
//```
//
//For the video, you can run the same UI flow against the simulator and record the simulator session.
//
//The exact recording mechanism is less important than the architecture:
//
//**the UI test is the canonical demo.**

//If you change:
//
//```swift
//app.buttons["Analyze"].tap()
//```
//
//to:
//
//```swift
//app.buttons["Analyze"].tap()
//app.buttons["Show Details"].tap()
//```
//
//you regenerate both your screenshots and your demo recording from the new flow.
//
//That's the bit that makes this sustainable.

//---
//
//# 11. Then GitHub Actions does the boring part
//
//Eventually your workflow becomes:
//
//```text
//git push
//   │
//   ▼
//GitHub Actions
//   │
//   ├── build app
//   │
//   ├── run DemoTests
//   │
//   ├── capture screenshots
//   │
//   ├── capture demo
//   │
//   └── build portfolio
//```
//
//GitHub provides macOS-hosted runners suitable for this sort of Xcode work; their current runner catalogue includes multiple macOS/Xcode configurations. ([GitHub Docs][4])
//
//Your `.github/workflows/portfolio.yml` can start very simply:
//
//```yaml
//name: Build Portfolio
//
//on:
//  push:
//    branches:
//      - main
//
//jobs:
//  portfolio:
//    runs-on: macos-latest
//
//    steps:
//      - name: Checkout
//        uses: actions/checkout@v4
//
//      - name: Select Xcode
//        run: |
//          sudo xcode-select -s /Applications/Xcode.app
//
//      - name: Install dependencies
//        run: |
//          bundle install
//
//      - name: Capture app
//        run: |
//          bundle exec fastlane snapshot
//
//      - name: Build portfolio
//        run: |
//          python3 scripts/build-portfolio.py
//```
//
//There will be some Xcode-version-specific fiddling here, so I wouldn't start by trying to make this CI-perfect.
//
//Get:
//
//```bash
//bundle exec fastlane snapshot
//```
//
//working **locally first**.
//
//Then move exactly that command into GitHub Actions.
//
//---

//# 12. And now the website
//
//I would keep this stupidly simple at first.
//
//Something like:
//
//```text
//portfolio/
//    index.html
//    apps/
//        my-app.html
//```
//
//Or use a static site generator.
//
//Your generated page essentially consumes:
//
//```text
//Portfolio/app.yml
//Portfolio/screenshots/*
//Portfolio/demo.mp4
//```

//and produces:
//
//```text
//My App
//──────────────────────────────
//
//An on-device ML app that...
//
//             [ iPhone ]
//
//        ▶ Watch the demo
//
//Screenshots
//──────────────────────────────
//
//[ screenshot ] [ screenshot ] [ screenshot ]
//
//About
//──────────────────────────────
//
//...
//
//Technical highlights
//──────────────────────────────
//
//SwiftUI · Core ML · ...
//
//Source
//──────────────────────────────
//
//GitHub
//```
//
//You could host the whole thing on GitHub Pages.
//
//---

//# 13. But there's a cleverer version for multiple apps
//
//Once you've done this once, I'd create a separate repo:
//
//```text
//ios-portfolio/
//│
//├── apps/
//│   ├── app-one.yml
//│   ├── app-two.yml
//│   └── app-three.yml
//│
//├── site/
//│   ├── index.html
//│   └── app.html
//│
//└── scripts/
//    └── build.py
//```
//
//Each actual app repository produces a small artifact:
//
//```text
//portfolio-artifact/
//├── app.yml
//├── screenshots/
//└── demo.mp4
//```
//
//Your portfolio repository consumes those.
//
//So eventually:
//
//```text
//                   ┌──────────────┐
//                   │   App One    │
//                   └──────┬───────┘
//                          │
//                       artifact
//                          │
//                          ▼
//                   ┌──────────────┐
//                   │              │
//                   │   PORTFOLIO  │
//                   │              │
//                   └──────────────┘
//                          ▲
//                          │
//                       artifact
//                          │
//                   ┌──────┴───────┐
//                   │   App Two    │
//                   └──────────────┘
//```
//
//You don't need to do this yet.
//
//---
//
//# 14. One thing I'd *not* do
//
//I wouldn't initially build a massive test architecture.
//
//Don't start with:
//
//```text
//UnitTests/
//IntegrationTests/
//UITests/
//Mocks/
//Fixtures/
//Factories/
//Protocols/
//Dependency injection framework/
//...
//```
//
//You're not trying to become a QA department.
//
//Start with:
//
//```text
//MyAppUITests/
//    DemoTests.swift
//    DemoHelpers.swift
//```
//
//Then you'll naturally discover things that should be abstracted.

//---
//
//# 15. The really nice side effect
//
//After doing this for 3–4 apps, your repos will have a consistent structure:
//
//```text
//MyFirstApp
//├── SwiftUI
//├── ML
//├── MyFirstAppUITests
//└── Portfolio
//
//MySecondApp
//├── SwiftUI
//├── ML
//├── MySecondAppUITests
//└── Portfolio
//
//MyThirdApp
//├── SwiftUI
//├── ML
//├── MyThirdAppUITests
//└── Portfolio
//```
//
//And your portfolio becomes a **catalogue of actual software**, rather than a catalogue of GitHub repositories.
//
//That's a much stronger signal.
//
//---
//
//## The implementation order I'd use
//
//Don't build all of this at once.
//
//### Phase 1 — ~1 app
//
//**Goal:** automatically generate 3 good screenshots.
//
//```text
//portfolio mode
//       ↓
//DemoTests.swift
//       ↓
//fastlane snapshot
//       ↓
//Portfolio/screenshots/
//```
//
//### Phase 2
//
//Add:
//
//```text
//DemoTests
//       ↓
//simulator recording
//       ↓
//demo.mp4
//```
//
//Now every project has a **15-second demo**.
//
//### Phase 3
//
//Build the static page:
//
//```text
//app.yml
//   +
//screenshots
//   +
//demo
//   ↓
//app.html
//```
//
//### Phase 4
//
//Move the whole thing to GitHub Actions.
//
//```text
//git push
//   ↓
//screenshots + video + website
//```
//
//### Phase 5
//
//Extract the common machinery into an **iOS portfolio template**.
//
//Then starting your next project can literally include:
//
//```text
//git clone ios-portfolio-app-template
//```
//
//and you've got the whole showcase apparatus already there.
//
//---
//
//## One final architectural recommendation
//
//I'd make **`DemoTests.swift` the centre of the system**, not the screenshots.
//
//Think of it as your app's *executable story*:
//
//```swift
//func testPortfolioDemo() {
//    launch()
//    capture("01-home")
//    createThing()
//    capture("02-created")
//    runML()
//    capture("03-ML-result")
//    exploreResult()
//    capture("04-details")
//}
//```
//
//That is essentially your **app's Jupyter notebook**.
//
//The notebook cells aren't screenshots sitting around waiting to go stale.
//
//They're **instructions that recreate the interesting states of your app**.
//
//And that's a surprisingly powerful abstraction for a portfolio of iOS projects.
//
//[1]: https://developer.apple.com/documentation/xcuiautomation/xcuiscreenshot?changes=la&language=objc&utm_source=chatgpt.com "XCUIScreenshot | Apple Developer Documentation"
//[2]: https://docs.fastlane.tools/getting-started/ios/screenshots/?utm_source=chatgpt.com "Screenshots - fastlane docs"
//[3]: https://developer.apple.com/documentation/xcode/testing?utm_source=chatgpt.com "Testing | Apple Developer Documentation"
//[4]: https://docs.github.com/en/actions/reference/runners/larger-runners?utm_source=chatgpt.com "Larger runners reference - GitHub Docs"


/*
// str -> str
run_tokeniser_core(thisText: String, lang: String, hyphen_join_value:Bool) -> String
runFRonlyReplacements(thisText: String) -> String

//str - >[Str]like
conllBlobToChunks(conllBlob: String) -> [String]
blobToSents(blob: String) -> [String]
getSentencesWithNL(text: String, lang: Language)-> [String]
getTokensFromText(inputText: String) -> [String]
tokeniseEN(inputString: String, selectedLang: Language) -> [Substring]
tokeniseFR(inputString: String, selectedLang: Language) -> [Substring]
markSentEndsNextTokApproach(tokens: [String], lang: String, approach: EosApproach) -> [Item]
applyNaiveTokenisation(language: Language, myString: String)-> [TempToken]
applySentencizingMethodToString(normalizedText: String, lang: Language, sentencizingMethod: SentencizingMethod) -> [String]
textFileToSentStrings(inputURL: URL?, sentencizingMethod: SentencizingMethod, lang: Language) -> [String]
 applyNaiveTokenisationToString(inputText: String) -> [String]

//str->[[Str]]
 getTokens(languageCode: String, method: TokenisationMethod, inputFile: String = "", targetString: String = "") -> [[String]]

 






//file->HashableSent

xmlToHashableSents(from url: URL?) throws -> [HashableSentence]
xmlToHashableSentForPipeline(inputURL: URL?) throws  -> [HashableSentence]
textFileToHashableSents(inputURL: URL?, sentencizingMethod: SentencizingMethod, tokenizingMethod: TokenizingMethod, lang: Language, pipeline: UDPipeline) throws -> [HashableSentence]

//str -> Hashable
stringSentsToHashableSents(tokenizingMethod: TokenizingMethod, sents: [String], lang: Language, pipeline: UDPipeline) throws -> [HashableSentence]
getTokenisedSentences(sents: [String], lang: Language) -> [HashableSentence]

makeHashableSentFromTestToks(tempTokens: [TempToken])-> HashableSentence?
markEosEnds(selectedLanguage: Language, tokListIn: [Substring])-> [EosTok]

*/

//  WordPieceTokenizer.swift
//
//  Builds the two inputs the converted DistilBERT model expects:
//
//      input_ids   [1, seqLen]    [CLS] + subwords of every word + [SEP], padded with the pad id
//      word_index  [1, maxWords]  position of each word's first subword; slot 0 is ROOT -> [CLS];
//                                 padded with -1
//
//  Each word is tokenised on its own, exactly as train_bert.py does it, using the same
//  pipeline as Hugging Face's BertTokenizerFast:
//
//      1. clean      drop NUL / U+FFFD / control characters, map whitespace to " "
//      2. CJK        put spaces around CJK ideographs (tokenize_chinese_chars)
//      3. accents    NFD, drop combining marks (only if stripping accents)
//      4. lowercase  per-scalar lowercase mapping (only if do_lower_case)
//      5. split      on whitespace; every punctuation character becomes its own token
//      6. WordPiece  greedy longest-match-first against vocab.txt, "##" for continuations;
//                    a token that can't be fully matched (or is > 100 characters) becomes [UNK]
//
//  A word that produces no pieces at all becomes a single [UNK], as in train_bert.py.
//
//  Everything works on Unicode scalars, not Swift Characters, because Python and Rust
//  iterate code points and Swift Characters merge combining sequences. The vocabulary is
//  keyed by UTF-8 bytes for the same reason: Swift String equality treats canonically
//  equivalent strings ("é" vs "e" + U+0301) as equal, which Python's dict does not.
//
//  Verify against Python with checkAgainstGolden(at:) before trusting any model output.
//
//  Not compiled or run when this was written, so treat the golden check as the real test.


//  BertPipeline.swift
//
//  Loading (tokenizer, Core ML model, label vocabularies) and annotate(...).
//
//  Written without your project's sources, so these names are assumptions:
//    Language, Treebank       your enums (used with .rawValue to build resource names)
//    Vocab.load(from: URL)    your vocab loader; swap in the real call (marked below)
//    resource naming          see "match your convention" comments
//  Not compiled.





// MARK: - Pipeline



// MARK: - Annotate

