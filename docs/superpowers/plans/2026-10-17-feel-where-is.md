# FEEL Where-is tool on the existing assistant — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `where_is(thing)` tool to FEEL's Grok assistant that photographs the scene once, asks a vision model through Chalk's gateway, places the answer with LiDAR, and keeps the puck pointing at it — with a Chalk evaluation that scores it.

**Architecture:** Pure geometry (`DepthGrid`, `HeldTarget`, `WhereIsPlacement`) goes in `FeelCore` and is tested on Linux. The `Lantern` app adds a Keychain-backed `ChalkConfiguration`, a `ChalkGateway` (URLSession), `ARPerception.snapshot`, a `WhereIsService`, one new `VoiceCommand` case executed by `LanternModel`, and a settings section in the Assistant modal. Evaluations run from `chalk/` against labeled photos.

**Tech Stack:** Swift 5.9+/SwiftUI/ARKit/CoreImage (iOS 16), XcodeGen, Python 3.13 + `chalkcompute`, Chalk Model Gateway with `openai/gpt-6.1-sol`.

**Spec:** `docs/superpowers/specs/2026-10-17-feel-where-is-design.md`

## Global Constraints

- Work on `feel/chalk-where-is` (= `origin/main` + the committed scaffold). No new branch.
- `FeelCore` has no UIKit/ARKit/URLSession/Security imports; `sh ios/scripts/test_portable.sh` passes on Mac and Linux.
- Nine-byte packet, firmware and `TactileEncoder.encode` unchanged.
- Secrets only in Keychain on the phone and git-ignored `chalk/.env`; never in source, plist or logs.
- Request bodies carry no `temperature`. Where-is timeout 20 s. Image long side ≤ 1024 px, JPEG quality 0.6.
- `thing` 1–60 characters, trimmed, no control characters. Puck field ±45° and 4 m. Reached radius 0.5 m.
- Spoken lines use the exact copy in the spec's tables. All announcements go through `GrokVoiceSession.announce`.
- Existing UI test identifiers stay valid; new ones: `chalkHost`, `chalkEnvironment`, `chalkKey`, `chalkModel`, `saveChalkSetup`, `chalkSetupError`.
- `bash scripts/check_ios.sh` (needs `brew install xcodegen` once) passes after every app task.
- Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Review Focus

1. `where_is` while the camera is stopped or in simulation must return an error result and take no photo and make no network call (Task 4 `testWhereIsRefusedUnlessLive`).
2. A "found" answer with no usable depth at the box centre (glass, beyond LiDAR range) must hold nothing and speak the "too far" line (Task 3 `testNoDepthGivesNoDepthOutcome`).
3. An ARKit restart with reset tracking while a target is held must clear it and speak "Lost tracking" — never point at stale coordinates (Task 1 `testEpochChangeInvalidates`, Task 4 `testWorldEpochChangeClearsHeldTarget`).
4. Gateway timeout or offline must produce the failed line; a second `where_is` must cancel the first so a late answer never places a target (Task 3 `testSecondRequestCancelsFirst`, `testGatewayErrorIsFailed`).
5. A malformed model reply (prose, box outside the image) must be a failed outcome and never a tap (Task 3 `testMalformedReplyIsFailed`).

---

### Task 0: Baseline

- [ ] **Step 1:** `git switch feel/chalk-where-is && git pull --ff-only && git log --oneline -1` → `ec672ee` or a descendant.
- [ ] **Step 2:** `sh ios/scripts/test_portable.sh` → "Executed 41 tests, with 0 failures". `(cd chalk && python3 -m unittest discover -s tests)` → "Ran 10 tests … OK".
- [ ] **Step 3:** `brew list xcodegen >/dev/null || brew install xcodegen`, then `bash scripts/check_ios.sh` → Lantern tests pass, Beacon builds. Note the app test count for later comparisons.

### Task 1: Held target, depth grid and placement (FeelCore)

**Files:**
- Create: `ios/Shared/FeelCore/Sources/FeelCore/DepthGrid.swift`
- Create: `ios/Shared/FeelCore/Sources/FeelCore/HeldTarget.swift`
- Test: `ios/Shared/FeelCore/Tests/FeelCoreTests/HeldTargetTests.swift`

**Interfaces:**
- Consumes: `CameraPose`, `CameraIntrinsics`, `Vector3`, `TargetObservation`, `TactileGeometry`, `WhereIsAnswer` (all existing).
- Produces:
  ```swift
  public struct DepthGrid: Equatable, Sendable {
      public let width: Int, height: Int, depths: [Double], confidence: [UInt8]
      public init(width: Int, height: Int, depths: [Double], confidence: [UInt8])
      public func medianDepth(x: Double, y: Double) -> Double?   // verbatim from ARPerception.DepthCopy: 5×5 window, confidence 1...2, 0 < d ≤ 4, ≥ 3 samples
  }
  public struct FrameSnapshot: Sendable {
      public let timestamp: Double, worldEpoch: Int, pose: CameraPose, intrinsics: CameraIntrinsics, depth: DepthGrid, jpegBase64: String
      public init(...)
  }
  public struct HeldTarget: Equatable, Sendable {
      public let position: Vector3, label: String, worldEpoch: Int, setAt: Double
      public init(position: Vector3, label: String, worldEpoch: Int, setAt: Double)
      public func observation(pose: CameraPose, now: Double, worldEpoch: Int) -> TargetObservation?
      public func relative(pose: CameraPose) -> (bearingDegrees: Double, horizontalDistance: Double)?
      public func reached(pose: CameraPose) -> Bool
      public func spokenDirection(pose: CameraPose) -> String?
  }
  public enum WhereIsPlacement {
      public static func place(answer: WhereIsAnswer, snapshot: FrameSnapshot) -> HeldTarget?   // nil when !found or no usable depth
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
final class HeldTargetTests: XCTestCase {
    // helpers: pose at origin facing −z; held(x, z) = HeldTarget(position: Vector3(x, 0, z), label: "desk", worldEpoch: 1, setAt: 0)
    func testObservationIsStampedNow()            // held(0,−2): observation(now: 7).timestamp == 7, bearing 0 ± 1e-9, distance 2, label "desk", confidence 1
    func testEpochChangeInvalidates()             // worldEpoch 2 → nil
    func testOutsideFieldHasNoObservationButSpeaks()  // held(−2, 0): observation nil; spokenDirection == "desk is to your left."
    func testBehindSpeaksBehind()                 // held(0, 2) → "desk is behind you."
    func testBeyondRangeSpeaksDistance()          // held(0, −6.4) → observation nil; "desk ahead, about 6 meters."
    func testInsideFieldSaysNothing()             // held(0, −2) → spokenDirection nil
    func testReached()                            // held(0, −0.3) → reached true; held(0, −0.6) → false
    func testPlacementUsesMedianDepthAtBoxCentre() // 20×10 grid, depth 2.0, confidence 2; intrinsics fx=fy=10,cx=10,cy=5; answer box (0.4,0.4,0.6,0.6) → position ≈ (0, 0, −2) ± 1e-6
    func testNoDepthGivesNoTarget()               // confidence 0 everywhere → nil
    func testNotFoundGivesNoTarget()              // found false → nil
}
```

- [ ] **Step 2:** `swift test --package-path ios/Shared/FeelCore --filter HeldTargetTests` → compile error, types undefined.
- [ ] **Step 3: Implement.** Bearing in `relative` is `atan2(x, -z)` on the camera-space point with no `z < 0` guard; `observation` builds `TargetObservation(bearingDegrees:distance:timestamp: now, confidence: 1, label:)` and returns it only if `valid(at: now)` and `worldEpoch` matches.
- [ ] **Step 4:** `sh ios/scripts/test_portable.sh` → 51 tests, 0 failures.
- [ ] **Step 5:** `git add ios/Shared/FeelCore && git commit -m "feat(core): held target, depth grid and Where-is placement"` (with trailer).

### Task 2: Chalk configuration and gateway in the app

**Files:**
- Create: `ios/Lantern/Services/KeychainStore.swift`
- Modify: `ios/Lantern/Services/VoiceConfiguration.swift` — `VoiceConfigurationStore` keeps its API, implemented with `KeychainStore<VoiceConfiguration>(service: "org.feel.hackharvard.voice", account: "token-service")`
- Create: `ios/Lantern/Services/ChalkGateway.swift`
- Test: `ios/LanternTests/ChalkGatewayTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct KeychainStore<Value: Codable> { init(service: String, account: String); func load() -> Value?; func save(_ value: Value) throws; func clear() }
  struct ChalkConfiguration: Codable, Equatable {
      let apiHost: String, routerApiKey: String, environmentId: String, model: String
      var url: URL?            // https, host present, no user/password/query/fragment (same rule as VoiceConfiguration.url)
      var isValid: Bool        // url != nil, key ≥ 16 chars without whitespace, environmentId 1...64, model non-empty
      static let defaultHost = "https://api.chalk.ai", defaultModel = "openai/gpt-6.1-sol"
  }
  struct ChalkConfigurationStore { func load() -> ChalkConfiguration?; func save(_:) throws; func clear() }   // KeychainStore, service "org.feel.hackharvard.chalk", account "gateway"
  protocol ChatGateway: AnyObject {
      @discardableResult func complete(body: Data, timeout: TimeInterval, completion: @escaping (Result<String, Error>) -> Void) -> URLSessionTask?
  }
  final class ChalkGateway: ChatGateway { init(configuration: ChalkConfiguration, session: URLSession = .shared) }
  // POST {url}/v1/router/chat/completions, headers Authorization: Bearer <key>, X-Chalk-Env-Id, Content-Type: application/json; returns choices[0].message.content; non-2xx or missing content → .failure
  ```

- [ ] **Step 1: Write the failing tests** — `testConfigurationValidation` (defaults valid with a 16-char key; http host → invalid; key with a space → invalid; empty model → invalid; 65-char environment → invalid), `testRequestCarriesGatewayHeaders` (a `URLProtocol` stub captures the request: URL ends with `/v1/router/chat/completions`, both headers, body echoed; stub replies `{"choices":[{"message":{"content":"OK"}}]}` → `.success("OK")`), `testMalformedReplyIsFailure` (`{}` → `.failure`), `testHTTPErrorIsFailure` (401 → `.failure`).
- [ ] **Step 2:** `bash scripts/check_ios.sh` → compile failure in LanternTests.
- [ ] **Step 3: Implement** the generic store, re-base `VoiceConfigurationStore` on it, and the gateway. The existing voice configuration tests in `GrokVoiceTests` must stay green.
- [ ] **Step 4:** `bash scripts/check_ios.sh` → all app tests pass.
- [ ] **Step 5:** `git add -A && git commit -m "feat(app): Chalk gateway client and Keychain configuration"` (with trailer).

### Task 3: Frame snapshot and Where-is service

**Files:**
- Modify: `ios/Lantern/Services/ARPerception.swift` — replace private `DepthCopy` with a Lantern extension `DepthGrid.init?(_ data: ARDepthData)`; add `worldEpoch` to `PerceptionFrame` (incremented in `start`); add `snapshot(completion:)`
- Create: `ios/Lantern/Services/WhereIsService.swift`
- Test: `ios/LanternTests/WhereIsServiceTests.swift`

**Interfaces:**
- Consumes: `ChatGateway`, `WhereIs.requestBody/parse`, `WhereIsPlacement`, `FrameSnapshot`, `HeldTarget`.
- Produces:
  ```swift
  // ARPerception
  func snapshot(completion: @escaping (FrameSnapshot?) -> Void)   // AR queue; nil unless currentFrame has normal tracking, valid mount and sceneDepth; completion on main
  // PerceptionFrame gains: let worldEpoch: Int
  enum WhereIsOutcome: Equatable { case placed(HeldTarget), notVisible, noDepth, failed }
  final class WhereIsService {
      init(gateway: ChatGateway, model: String)
      func find(_ thing: String, snapshot: FrameSnapshot, completion: @escaping (WhereIsOutcome) -> Void)   // question "Where is the <thing>?"; cancels any in-flight request; completion on main, at most once per call
  }
  ```

- [ ] **Step 1: Write the failing tests** with a stub `ChatGateway` and the synthetic snapshot from Task 1:
  `testFoundPlacesTarget` (stub returns the shared "found" case text → `.placed` with label "registration desk"), `testNotFoundIsNotVisible`, `testNoDepthGivesNoDepthOutcome` (confidence-0 grid), `testMalformedReplyIsFailed` (stub returns "The desk is on your right."), `testGatewayErrorIsFailed`, `testSecondRequestCancelsFirst` (first stub never completes; second completes; exactly one outcome delivered, for the second), `testRequestAsksWhereIsThing` (captured body's user text == "Where is the desk?").
- [ ] **Step 2:** `bash scripts/check_ios.sh` → compile failure.
- [ ] **Step 3: Implement.** JPEG: `CIImage(cvPixelBuffer:)` scaled so the long side ≤ 1024, `CIContext().jpegRepresentation(of:colorSpace:options: [kCGImageDestinationLossyCompressionQuality: 0.6])`, base64. Intrinsics scaled to the depth grid exactly as `session(_:didUpdate:)` does (factor that into a private helper used by both).
- [ ] **Step 4:** `bash scripts/check_ios.sh` → all app tests pass.
- [ ] **Step 5:** `git add -A && git commit -m "feat(app): frame snapshot and Where-is service through Chalk"` (with trailer).

### Task 4: The `where_is` tool and held-target guidance

**Files:**
- Modify: `ios/Lantern/Services/VoiceCommand.swift` — `case whereIs(String)`, decode, tool definition, two instruction lines (exact copy in the spec)
- Modify: `ios/Lantern/Services/VoicePhrasing.swift` — `static func observation(_ target: TargetObservation, named label: String, now: TimeInterval) -> String?` ("The <label> was 3 meters to your right.", same rounding and side rules)
- Modify: `ios/Lantern/Models/LanternModel.swift` — `chalkStore`, `whereIsConfiguration`, `whereIsService`, `heldTarget`, `whereIsNotice`; `performVoiceCommand(.whereIs)`; `handleWhereIs(_:thing:)`; held target in `tick()`; clear rules; `voiceSnapshot` adds `where_is_available`, `held_target`, `where_is`
- Modify: `docs/V1-VOICE.md` — add Where-is to the supported requests and the setup section
- Test: `ios/LanternTests/GrokVoiceTests.swift` (extend the allowlist test), `ios/LanternTests/WhereIsCommandTests.swift`

**Interfaces:**
- Consumes: `WhereIsService`, `ChalkConfigurationStore`, `HeldTarget`, `GrokVoiceSession.announce(_:automatic:sceneBound:)`, `VoiceCommand`.
- Produces (internal, for tests):
  ```swift
  // LanternModel
  @Published private(set) var heldTarget: HeldTarget?
  private(set) var whereIsNotice: String?
  var whereIsAvailable: Bool            // configuration valid && mode == .live && guidanceState == .live
  func saveChalkConfiguration(_:) throws; func forgetChalkConfiguration()
  func handleWhereIs(_ outcome: WhereIsOutcome, thing: String)   // main queue; spec's outcome table
  func clearHeldTarget(spokenLine: String?)
  ```
  Decision execution per the spec's tables. In `tick()`: `let held = heldTarget?.observation(pose: frame.pose, now: now, worldEpoch: frame.worldEpoch)`; `let target = held ?? (finder == .teammate ? peer.currentTarget(...) : frame.target)`; `voiceTargetPhrase` uses the named overload when `held != nil`; after encoding, apply reached / epoch-changed / spoken-direction rules. `.find` and `stop()` clear silently.

- [ ] **Step 1: Write the failing tests**
  - In `testCommandAllowlistRejectsMalformedAndUnsafeArguments`: `decode("where_is", "{\"thing\":\"registration desk\"}") == .whereIs("registration desk")`; rejects `{}`, `{"thing":""}`, a 61-character thing, a thing with `\u{0007}`, and `{"thing":"desk","extra":1}`.
  - `WhereIsCommandTests` (model built with the fake voice session from `GrokVoiceTests`, a stub gateway, and a stub configuration store):
    `testWhereIsRefusedUnlessLive` (stopped and simulation → `["error"]` present; the stub gateway saw zero calls),
    `testWhereIsRefusedWithoutConfiguration`,
    `testPlacedOutcomeHoldsTargetAndSnapshotReportsIt` (`handleWhereIs(.placed(held), thing: "desk")` → `heldTarget != nil`, `voiceSnapshot()["held_target"] as? String == "desk"`),
    `testNotVisibleKeepsNoticeWhenAnnounceCannotSpeak` (voice idle → `whereIsNotice == "I couldn't see a desk in the photo."`, `voiceSnapshot()["where_is"]` equals it),
    `testStopClearsHeldTarget`, `testFindClearsHeldTarget`,
    `testWorldEpochChangeClearsHeldTarget` (hold with epoch 1, call `clearHeldTarget` path through the perception `onInvalidated` closure → `heldTarget == nil`, notice "Lost tracking. Say it again."),
    `testNamedObservationPhrase` (`VoicePhrasing.observation(TargetObservation(bearingDegrees: 30, distance: 3, timestamp: 1), named: "desk", now: 1) == "The desk was 3 meters to your right."`).
- [ ] **Step 2:** `bash scripts/check_ios.sh` → compile failure.
- [ ] **Step 3: Implement** the command, phrasing overload, model wiring and the doc lines.
- [ ] **Step 4:** `bash scripts/check_ios.sh` → all tests pass, including V1's UI tests.
- [ ] **Step 5:** `git add -A && git commit -m "feat(app): where_is tool with held target and spoken direction"` (with trailer).

### Task 5: Where-is settings in the Assistant modal

**Files:**
- Modify: `ios/Lantern/Views/VoiceControls.swift` — a "Where-is setup" section at the end of `VoiceSetup`
- Test: `ios/LanternUITests/LanternUITests.swift` — `testWhereIsSetupValidatesAndSaves`

**Interfaces:**
- Consumes: `LanternModel.saveChalkConfiguration(_:)`, `forgetChalkConfiguration()`, `ChalkConfiguration.defaultHost/defaultModel`.
- Produces identifiers: `chalkHost`, `chalkEnvironment`, `chalkKey`, `chalkModel`, `saveChalkSetup`, `chalkSetupError`.

- [ ] **Step 1: Write the failing UI test:** open the Assistant modal (`voiceControl`), fill `chalkEnvironment` with `bnsb82aac313`, `chalkKey` with a 16-character test value, leave host/model prefilled, tap `saveChalkSetup`; assert `chalkSetupError` is absent and the section shows "Where-is ready". Then tap Save with an empty key and assert `chalkSetupError` exists.
- [ ] **Step 2:** `bash scripts/check_ios.sh` → the new UI test fails.
- [ ] **Step 3: Implement** the section: heading "Where-is setup", one footnote ("Where is X? sends one camera photo through Chalk's gateway to a vision model. Settings stay in Keychain."), four fields with the identifiers above, Save (`FeelPrimaryButtonStyle`), Forget (destructive, shown when configured), status line "Where-is ready" / "Where-is not set up". `VoiceSetup` gains `@ObservedObject var model: LanternModel` (or a small binding struct) for save/forget.
- [ ] **Step 4:** `bash scripts/check_ios.sh` → all tests pass.
- [ ] **Step 5:** `git add -A && git commit -m "feat(app): Where-is settings in the Assistant modal"` (with trailer).

### Task 6: Chalk evaluation and README

**Files:**
- Modify: `chalk/feel_chalk/where_is_eval.py` — resolve the TODO: scorer per Chalk's custom-scorer contract, `--model` flag, suite name `feel-where-is`
- Create: `chalk/evals/validate_labels.py` — exits nonzero if a row is malformed, an image is missing, or fewer than a third of rows have `box: null`
- Modify: `chalk/README.md`, `README.md` — "Where Chalk is used"
- Test: `chalk/tests/test_labels.py`

- [ ] **Step 1: Write the failing test** `test_validator_accepts_example_and_rejects_bad_rows` (the example file with two rows passes; a row with a missing image or a box outside 0...1 fails; a set with no `null` rows fails).
- [ ] **Step 2:** `cd chalk && python3 -m unittest tests.test_labels -v` → ImportError.
- [ ] **Step 3: Implement** the validator and the eval changes (read `https://docs.chalk.ai/docs/evaluations/scorers.md` "Writing your own" for the signature).
- [ ] **Step 4:** `cd chalk && python3 -m unittest discover -s tests -v` → 11 tests OK.
- [ ] **Step 5: Collect data.** Take 20–30 photos at the venue from chest height with the team's consent (no bystanders' faces), save under `chalk/data/photos/`, label in `chalk/data/labels.jsonl`; `python3 evals/validate_labels.py data/labels.jsonl` → "N rows valid".
- [ ] **Step 6: Run on Chalk** (needs `chalk login` and `chalk environment bnsb82aac313`): `.venv/bin/python -m feel_chalk.where_is_eval data/labels.jsonl --model openai/gpt-6.1-sol` and again with `--model openai/gpt-6-luna` → `SUCCEEDED`. If refused for missing Evaluations, ask the Chalk team on Slack and record BLOCKED.
- [ ] **Step 7:** Write the README sections with the measured pointing accuracy, correct-not-found rate and false-found rate per model, and the run IDs.
- [ ] **Step 8:** `git add -A && git commit -m "feat(chalk): Where-is evaluation on venue photos and README"` (with trailer).

### Task 7: Device verification (phone, Chalk and xAI configured)

- [ ] **Step 1:** Install on the LiDAR iPhone; enter Chalk settings in the Assistant modal; start the camera; calibrate.
- [ ] **Step 2:** Say "where is the chair" → confirmation within 1 s, spoken observation and pin within 6 s; turn 90° → pin follows; walk to it → "You're at the chair."
- [ ] **Step 3:** Say "where is the refrigerator" (none present) → "I couldn't see a refrigerator in the photo."; no pin change.
- [ ] **Step 4:** Hold a target, cover the camera until tracking resets → "Lost tracking. Say it again."; pins neutral.
- [ ] **Step 5:** Hold a target, turn your back to it → "chair is behind you." within 5 s; "stop" → highlight off, obstacles still shown.
- [ ] **Step 6:** Record PASS/FAIL/NOT RUN per step with the commit in `docs/RELEASE-STATUS.md`; commit.
