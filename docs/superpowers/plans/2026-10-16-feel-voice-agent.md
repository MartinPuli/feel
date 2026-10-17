# FEEL V4 voice agent, Where-is and judge view — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a blind FEEL user say what they want in their own words; an agent picks one app tool, confirms in a few words, and the puck guides them — including "where is X?" placed in the room with LiDAR — with a judge view and Chalk evaluations that prove it.

**Architecture:** Pure contract code (prompt, reply parser, context rendering, held target, depth placement) lives in `FeelCore` and is mirrored in `chalk/feel_chalk` so both are tested against shared files in `protocol/`. The `Lantern` app adds a `ChalkGateway` (URLSession), an `AgentService` that tries V3's grammar before the model, a `WhereIsService` that snapshots the AR frame and places the answer, and a restructured judge-view UI. Chalk evaluations run from `chalk/`.

**Tech Stack:** Swift 5.9+/SwiftUI/ARKit/Speech (iOS 16), XcodeGen, Python 3.13 + `chalkcompute`, Chalk Model Gateway (OpenAI-compatible chat completions).

**Spec:** `docs/superpowers/specs/2026-10-16-feel-voice-agent-design.md`

## Global Constraints

- Base branch `origin/feel/v3-advanced`; new branch `feel/v4-agent`; merge `feel/chalk-where-is` first.
- `FeelCore` has no UIKit/ARKit/URLSession imports; `sh ios/scripts/test_portable.sh` must pass on Mac and Linux.
- Nine-byte packet, firmware and `TactileEncoder.encode` signature unchanged.
- Secrets only in git-ignored `ios/Lantern/ChalkSecrets.plist` and `chalk/.env`.
- Confirmations ≤ 12 words; `say` 1–120 characters; `name` 1–40; `thing` 1–60; `question` 1–120.
- Timeouts: agent model call 12 s; Where-is call 20 s. Spoken coarse direction at most every 3 s. Reached radius 0.5 m. Puck field ±45°, 4 m.
- V3 UI test identifiers stay valid (`memorySimulation`, `targetStatus`, `commandText`, `runCommand`, `voiceStatus`, `commandNotice`, `placeName`, `rememberPlace`, `recallPlace`, `setReturnPoint`, `returnToPoint`, `stopMemoryGuidance`, `savedPlaces`, `placesCount`, `memoryNotice`, `mapNotice`, `adaptiveProfile`).
- Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Review Focus

1. A model reply with a real tool but an out-of-enum argument (`find` with `kind: "exit sign"`) must be malformed → spoken fallback, pins unchanged (Task 1 cases 7, 11).
2. Where-is "found" with no usable depth at the box centre (glass, beyond 4 m) must produce no target and the "too far" line (Task 6 test `testNoDepthGivesNoTarget`).
3. AR interruption while a target is held must drop the target and its highlight (Task 4 `testEpochChangeInvalidates`).
4. No network: grammar commands still work and never touch the gateway; a model call that errors or times out speaks the fallback; a second utterance cancels the first call (Task 7 tests).
5. Overlong or control-character transcripts must never reach the model (Task 7 `testOverlongTranscriptNeverCallsGateway`).

---

### Task 0: Branch, merge and baseline

**Files:**
- Branch: `feel/v4-agent` from `origin/feel/v3-advanced`
- Merge: `feel/chalk-where-is` (brings `chalk/`, `protocol/where-is-*`, `WhereIs.swift`, tests, this spec and plan)

- [ ] **Step 1: Commit the scaffold, then create the branch and merge**

The Chalk scaffold, the spec and this plan are uncommitted on `feel/chalk-where-is`
(that branch still points at the V1 commit). Commit them there first, or the merge
brings nothing:

```bash
git switch feel/chalk-where-is
git add -A && git commit -m "feat(chalk): Where-is scaffold, gateway client, contract tests and V4 design

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git switch -c feel/v4-agent origin/feel/v3-advanced
git merge --no-edit feel/chalk-where-is
```
Resolve conflicts in `.gitignore` or `ios/project.yml` by keeping both sides.

- [ ] **Step 2: Run the baseline**

Run: `sh ios/scripts/test_portable.sh && (cd chalk && python3 -m unittest discover -s tests -v)`
Expected: Swift "Executed 93 tests, with 0 failures" (90 V3 + 3 WhereIs); Python "Ran 10 tests … OK".

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "chore: start V4 agent branch from V3 with Chalk Where-is scaffold

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 1: Agent contract and Swift reply parser

**Files:**
- Create: `protocol/agent-prompt.txt` (exact prompt from the spec)
- Create: `protocol/agent-cases.json`
- Create: `ios/Shared/FeelCore/Sources/FeelCore/Agent.swift`
- Test: `ios/Shared/FeelCore/Tests/FeelCoreTests/AgentTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum AgentTool: String, CaseIterable, Sendable { case find, whereIs = "where_is", remember, recall, returnToPoint = "return", listPlaces = "list_places", stop, status, ask, none }
  public enum AgentDecision: Equatable, Sendable { case find(VoiceFindMode), whereIs(String), remember(String), recall(String), returnToPoint, listPlaces, stop, status, ask(String), none }
  public struct AgentReply: Equatable, Sendable { public let decision: AgentDecision; public let say: String }
  public enum AgentError: Error, Equatable { case malformed(String) }
  public enum Agent {
      public static let prompt: String                      // == protocol/agent-prompt.txt, trimmed
      public static func parse(_ text: String) throws -> AgentReply
  }
  ```

- [ ] **Step 1: Write the shared cases file** `protocol/agent-cases.json` with `{"cases":[…]}`, each `{"name","text","expect":{"tool":…, "kind"|"name"|"thing"|"question":…, "say":…}}` or `{"name","text","error":true}`:
  1. `find exit` → text `{"tool":"find","args":{"kind":"exit"},"say":"Looking for exits."}`
  2. `where_is` → `{"tool":"where_is","args":{"thing":"registration desk"},"say":"Looking for the registration desk."}`
  3. `ask` → `{"tool":"ask","args":{"question":"Which place?"},"say":"Which place?"}`
  4. `none` → `{"tool":"none","args":{},"say":"I can't turn off obstacle sensing."}`
  5. `remember` → `{"tool":"remember","args":{"name":"my seat"},"say":"Remembered my seat."}`
  6. `code fence tolerated` → ```` ```json\n{"tool":"stop","args":{},"say":"Stopped."}\n``` ```` → stop
  7. `kind outside enum` → `{"tool":"find","args":{"kind":"exit sign"},"say":"ok"}` → error
  8. `unknown tool` → `{"tool":"disable_obstacles","args":{},"say":"Done."}` → error
  9. `missing say` → `{"tool":"stop","args":{}}` → error
  10. `prose` → `Sure, looking for exits.` → error
  11. `name too long` → remember with a 41-character name → error
  12. `extra args ignored` → `{"tool":"return","args":{"x":1},"say":"Going back."}` → returnToPoint
  13. `say too long` → stop with a 121-character say → error

- [ ] **Step 2: Write the failing tests**

```swift
final class AgentTests: XCTestCase {
    func testPromptMatchesSharedFile()   // Agent.prompt == contents of protocol/agent-prompt.txt, trimmed (locate protocol/ as WhereIsTests does)
    func testSharedParserCases()         // every case: error cases throw AgentError; others match decision and say
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --package-path ios/Shared/FeelCore --filter AgentTests`
Expected: compile error, `Agent` not defined.

- [ ] **Step 4: Implement `Agent.swift`** with the interfaces above. Parse with `JSONDecoder` into `struct Raw: Decodable { tool: String; args: [String: AnyCodable-like]; say: String? }` — simplest is `JSONSerialization` to `[String: Any]`; validate per the spec's reply rules; map `kind` through `VoiceFindMode(rawValue:)`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `sh ios/scripts/test_portable.sh`
Expected: 95 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add protocol/agent-prompt.txt protocol/agent-cases.json ios/Shared/FeelCore
git commit -m "feat(core): agent reply contract and parser

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 2: Context rendering, grammar decisions and request body

**Files:**
- Modify: `ios/Shared/FeelCore/Sources/FeelCore/Agent.swift`
- Test: `ios/Shared/FeelCore/Tests/FeelCoreTests/AgentTests.swift`

**Interfaces:**
- Consumes: `VoiceIntent`, `VoiceFindMode`, `VoiceLanguage` (V3 `VoiceIntent.swift`).
- Produces:
  ```swift
  public struct AgentContext: Equatable, Sendable {
      public var language: VoiceLanguage, finder: VoiceFindMode, floorCalibrated: Bool, puckConnected: Bool, places: [String], teammates: [String], whereIsAvailable: Bool
      public func render() -> String          // exact block from the spec; empty lists print "none"
  }
  extension Agent {
      public static func reply(for intent: VoiceIntent, language: VoiceLanguage) -> AgentReply   // grammar path, fixed confirmations
      public static func requestBody(model: String, context: AgentContext, utterance: String) throws -> Data
      public static let fallbackSay = "I didn't catch that. Try: find exit, or: where is the desk."
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
func testContextRendersExactly() {
    let c = AgentContext(language:.en, finder:.obstacles, floorCalibrated:true, puckConnected:false, places:["my seat","entrance"], teammates:["Sarah"], whereIsAvailable:true)
    XCTAssertEqual(c.render(), "Context:\nlanguage: en\nfinder: obstacles\nfloor calibrated: yes\npuck connected: no\nsaved places: my seat, entrance\nteammates: Sarah\ncamera available for where_is: yes")
}
func testEmptyListsRenderNone()          // places: [] → "saved places: none"; teammates: [] → "teammates: none"
func testGrammarConfirmations() {
    XCTAssertEqual(Agent.reply(for:.find(.exit), language:.en), AgentReply(decision:.find(.exit), say:"Looking for exits."))
    XCTAssertEqual(Agent.reply(for:.stop, language:.en).say, "Stopped. Obstacles still on.")
    XCTAssertEqual(Agent.reply(for:.remember("my seat"), language:.en).say, "Remembered my seat.")
    XCTAssertEqual(Agent.reply(for:.returnToPoint, language:.en).say, "Going back.")
}
func testRequestBodyLayout() {
    // messages[0] = system prompt; messages[1] = user context.render(); messages[2] = user utterance; model echoed; no temperature key (current Anthropic models reject it)
}
```

- [ ] **Step 2: Run tests to verify they fail** — `swift test --package-path ios/Shared/FeelCore --filter AgentTests` → compile error.

- [ ] **Step 3: Implement** the context, the confirmation table (English exact per spec; Spanish builder's translation keyed by `language`), and the request body (`JSONSerialization`, `.sortedKeys`).

- [ ] **Step 4: Run tests** — `sh ios/scripts/test_portable.sh` → 99 tests, 0 failures.

- [ ] **Step 5: Commit** — `git commit -am "feat(core): agent context, grammar confirmations and request body"` (with trailer).

### Task 3: Python mirror of the agent contract

**Files:**
- Create: `chalk/feel_chalk/agent.py`
- Test: `chalk/tests/test_agent.py`

**Interfaces:**
- Produces:
  ```python
  PROMPT: str                                   # == protocol/agent-prompt.txt
  FALLBACK_SAY: str
  @dataclass(frozen=True) class Reply: tool: str; args: dict; say: str
  class AgentError(ValueError)
  def parse(text: str) -> Reply                 # same rules as Swift; returns tool as the wire name ("where_is", "return", …)
  def render_context(language: str, finder: str, floor_calibrated: bool, puck_connected: bool, places: list[str], teammates: list[str], where_is_available: bool) -> str
  def request_body(model: str, context_text: str, utterance: str) -> dict
  ```

- [ ] **Step 1: Write the failing tests** — `test_prompt_matches_shared_file`, `test_shared_parser_cases` (every case in `protocol/agent-cases.json`; compare `tool` and the one arg named in `expect`), `test_context_renders_exactly` (same string as the Swift test), `test_request_body_layout`.
- [ ] **Step 2: Run** `cd chalk && python3 -m unittest tests.test_agent -v` → ImportError.
- [ ] **Step 3: Implement `agent.py`** following `where_is.py`'s style (fence tolerance, strict types, bool-is-not-number check).
- [ ] **Step 4: Run** `cd chalk && python3 -m unittest discover -s tests -v` → 14 tests OK.
- [ ] **Step 5: Commit** — `git add chalk && git commit -m "feat(chalk): python mirror of the agent contract"` (with trailer).

### Task 4: Held target and depth placement (FeelCore)

**Files:**
- Create: `ios/Shared/FeelCore/Sources/FeelCore/HeldTarget.swift`
- Create: `ios/Shared/FeelCore/Sources/FeelCore/DepthGrid.swift`
- Modify: `ios/Lantern/Services/ARPerception.swift` — replace private `DepthCopy` storage with `DepthGrid` (keep the `init?(ARDepthData)` in Lantern as an extension that builds a `DepthGrid`)
- Test: `ios/Shared/FeelCore/Tests/FeelCoreTests/HeldTargetTests.swift`

**Interfaces:**
- Consumes: `CameraPose`, `CameraIntrinsics`, `Vector3`, `TargetObservation`, `TactileGeometry`, `WhereIsAnswer`.
- Produces:
  ```swift
  public struct DepthGrid: Equatable, Sendable {
      public let width: Int, height: Int, depths: [Double], confidence: [UInt8]
      public init(width: Int, height: Int, depths: [Double], confidence: [UInt8])
      public func medianDepth(x: Double, y: Double) -> Double?     // moved verbatim from ARPerception.DepthCopy
  }
  public struct FrameSnapshot: Sendable {
      public let timestamp: Double, epoch: Int, pose: CameraPose, intrinsics: CameraIntrinsics, depth: DepthGrid, jpegBase64: String
  }
  public struct HeldTarget: Equatable, Sendable {
      public let position: Vector3, label: String, epoch: Int, setAt: Double
      public func observation(pose: CameraPose, now: Double, epoch: Int) -> TargetObservation?   // nil if epoch differs, pose invalid, outside ±45°, or band 0
      public func relative(pose: CameraPose) -> (bearingDegrees: Double, horizontalDistance: Double)?  // full circle, left negative, 0 ahead
      public func reached(pose: CameraPose) -> Bool                                                  // horizontalDistance < 0.5
      public func spokenDirection(pose: CameraPose) -> String?                                       // spec §Where-is step 6; nil when the puck shows it
  }
  public enum WhereIsPlacement {
      public static func place(answer: WhereIsAnswer, snapshot: FrameSnapshot) -> HeldTarget?       // nil when not found or no usable depth
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
func testObservationIsStampedNow()        // target 2 m ahead: observation.timestamp == now, bearing 0, band 3, label kept
func testEpochChangeInvalidates()         // epoch 2 vs held epoch 1 → nil
func testOutsideFieldHasNoObservationButSpeaks()  // target at bearing −90: observation nil; spokenDirection == "desk is to your left."
func testBehindSpeaksBehind()             // bearing 170 → "desk is behind you."
func testBeyondRangeSpeaksDistance()      // 6.4 m ahead → observation nil; "desk ahead, about 6 meters."
func testInsideFieldSaysNothing()         // 2 m ahead → spokenDirection nil
func testReached()                        // 0.3 m ahead → reached true
func testPlacementUsesMedianDepthAtBoxCentre()    // 20×10 grid, depth 2.0 with confidence 2 everywhere; box centre (0.5,0.5); intrinsics fx=fy=10,cx=10,cy=5 → position ≈ pose.worldPoint of (0,0,−2)
func testNoDepthGivesNoTarget()           // confidence 0 everywhere → nil
func testNotFoundGivesNoTarget()
```

- [ ] **Step 2: Run** `swift test --package-path ios/Shared/FeelCore --filter HeldTargetTests` → compile error.
- [ ] **Step 3: Implement** `DepthGrid` (move the median code), `HeldTarget` (bearing via `atan2(x, -z)` on the camera-space point, no `z<0` guard; `observation` builds a `TargetObservation(bearingDegrees:distance:timestamp:now,confidence:1,label:)` and returns it only if `valid(at:now)`), `WhereIsPlacement.place` (centre → pixel → `medianDepth` → `unproject` → `worldPoint`). Update `ARPerception` to build a `DepthGrid` and call its `medianDepth`.
- [ ] **Step 4: Run** `sh ios/scripts/test_portable.sh` → 109 tests, 0 failures. Then `swift build --package-path ios/Shared/FeelCore` builds.
- [ ] **Step 5: Commit** — `git commit -am "feat(core): held target, depth grid and Where-is placement"` (with trailer).

### Task 5: Chalk config and gateway client in the app

**Files:**
- Create: `ios/Lantern/Services/ChalkGateway.swift`
- Create: `ios/Lantern/ChalkSecrets.example.plist`
- Modify: `.gitignore` (add `ios/Lantern/ChalkSecrets.plist`)
- Modify: `ios/project.yml` (nothing new required: XcodeGen picks up files under `Lantern`; add `NSMicrophoneUsageDescription`/`NSSpeechRecognitionUsageDescription` only if absent — V3 already has them)
- Test: `ios/LanternTests/ChalkGatewayTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct ChalkConfig: Equatable { let apiHost: URL, routerApiKey: String, environmentId: String, model: String
      static func load(bundle: Bundle = .main) -> ChalkConfig?          // nil when the plist or any key is missing/empty
      static func load(plist: [String: Any]) -> ChalkConfig? }
  protocol ChatGateway { @discardableResult func complete(body: Data, timeout: TimeInterval, completion: @escaping (Result<String, Error>) -> Void) -> URLSessionTask? }
  final class ChalkGateway: ChatGateway { init(config: ChalkConfig, session: URLSession = .shared) }   // POST {apiHost}/v1/router/chat/completions, headers per spec; returns choices[0].message.content or throws
  ```

- [ ] **Step 1: Write the failing tests** — `testLoadRejectsMissingKey` (plist without `model` → nil), `testLoadParsesExample` (the example plist with placeholder values → non-nil), `testRequestHasGatewayHeaders` (use a `URLProtocol` stub to capture the request: URL, `Authorization`, `X-Chalk-Env-Id`, body echoed), `testMalformedReplyIsError`.
- [ ] **Step 2: Run** `bash scripts/check_ios.sh` (installs nothing; needs `brew install xcodegen` once) → compile failure in LanternTests.
- [ ] **Step 3: Implement** the config loader and gateway; the example plist holds `apiHost = https://api.chalk.ai`, other keys empty strings.
- [ ] **Step 4: Run** `bash scripts/check_ios.sh` → Lantern tests pass (26+ app tests), Beacon builds.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(app): Chalk gateway client and git-ignored config"` (with trailer).

### Task 6: Where-is service in the app

**Files:**
- Modify: `ios/Lantern/Services/ARPerception.swift` — add `func snapshot(completion: @escaping (FrameSnapshot?) -> Void)` run on the AR queue (JPEG from `frame.capturedImage` via `CIImage`/`CIContext`, long side ≤ 1024, quality 0.6)
- Create: `ios/Lantern/Services/WhereIsService.swift`
- Modify: `ios/Lantern/Models/LanternModel.swift` — hold the target, feed it to the encoder in `tick()`, clear rules, spoken cadence
- Test: `ios/LanternTests/WhereIsServiceTests.swift`

**Interfaces:**
- Consumes: `ChatGateway`, `WhereIs.requestBody/parse`, `WhereIsPlacement`, `HeldTarget`, `VoiceControl.speak`.
- Produces:
  ```swift
  final class WhereIsService {
      init(gateway: ChatGateway, model: String)
      func find(_ thing: String, snapshot: FrameSnapshot, completion: @escaping (WhereIsOutcome) -> Void)   // cancels any in-flight request
  }
  enum WhereIsOutcome: Equatable { case placed(HeldTarget), notVisible(String), noDepth(String), failed(String) }   // associated String = spoken line
  // LanternModel additions
  @Published private(set) var heldTarget: HeldTarget?
  func whereIs(_ thing: String)      // speaks "Looking for the X." first; requires mode == .live, calibrated frame, tracking true
  func clearHeldTarget(reason: String?)   // speaks reason when non-nil
  ```
  Spoken lines (exact): notVisible → `"I can't see a \(thing) from here."`; noDepth → `"I see it but it's too far to point at."`; failed → `Agent.fallbackSay`; reached → `"You're at the \(label)."`; epoch change → `"Lost tracking. Say it again."`

- [ ] **Step 1: Write the failing tests** with a stub gateway and a synthetic `FrameSnapshot` (reuse the grid from Task 4):
  `testFoundPlacesTarget`, `testNotFoundSpeaksNotVisible`, `testNoDepthGivesNoTarget` (confidence 0 grid → `.noDepth`), `testMalformedReplyFails`, `testSecondRequestCancelsFirst` (first stub never completes; second completes; only the second outcome is delivered).
- [ ] **Step 2: Run** `bash scripts/check_ios.sh` → compile failure.
- [ ] **Step 3: Implement** the service and the model wiring: in `tick()`, `let target = heldTarget?.observation(pose:frame.pose, now:now, epoch:frame.epoch) ?? (finder == .teammate ? peer.currentTarget(...) : frame.target)`; after encoding, if `heldTarget.reached(pose)` → clear with the reached line; if `frame.epoch != heldTarget.epoch` → clear with the lost line; every ≥3 s, `spokenDirection` non-nil → speak. `stop()` clears silently.
- [ ] **Step 4: Run** `bash scripts/check_ios.sh` → all app tests pass.
- [ ] **Step 5: Commit** — `git commit -am "feat(app): Where-is capture, placement and held target"` (with trailer).

### Task 7: Agent service and voice wiring

**Files:**
- Create: `ios/Lantern/Services/AgentService.swift`
- Modify: `ios/Lantern/Models/LanternModel.swift` — `executeCommand(_:)` routes through the agent; add `@Published lastTrace: AgentTrace?`, `agentStatus: String`
- Test: `ios/LanternTests/AgentServiceTests.swift`

**Interfaces:**
- Consumes: `VoiceIntentParser`, `VoiceTranscriptPolicy.final`, `Agent.*`, `ChatGateway`, `AgentContext`.
- Produces:
  ```swift
  struct AgentTrace: Equatable { enum Route: String { case grammar, model, fallback }
      let heard: String, route: Route, tool: String, args: String, said: String, latencyMs: Int }
  final class AgentService {
      init(gateway: ChatGateway?, model: String?)                                    // nil gateway → grammar only
      func route(text: String, context: AgentContext, completion: @escaping (AgentReply, AgentTrace) -> Void)
  }
  ```
  Behaviour: `VoiceTranscriptPolicy.final(text)` nil → fallback reply, route `.fallback`, no gateway call. Grammar match → `Agent.reply(for:language:)`, route `.grammar`, no gateway call. Otherwise gateway with 12 s timeout; parse → `.model`; any error/timeout → fallback. A new `route` cancels the in-flight task. `LanternModel` executes the decision through its existing actions (`finder = …`, `remember/recall/returnToPoint/listPlaces/stopMemoryGuidance`, `whereIs(_:)`, `stop` semantics per spec, `status` composed line) and speaks `say` via `voice.speak`. `.whereIs` with `!context.whereIsAvailable` → speak "I can't look right now." and do nothing else.

- [ ] **Step 1: Write the failing tests** with a stub gateway that records calls:
  `testGrammarNeverCallsGateway` ("find exit" → `.find(.exit)`, calls == 0), `testModelPathParsesReply` (stub returns the where_is case text → `.whereIs("registration desk")`, route `.model`), `testGatewayErrorFallsBack` (say == `Agent.fallbackSay`, route `.fallback`), `testNoGatewayIsGrammarOnly` (unmatched text → fallback, no crash), `testOverlongTranscriptNeverCallsGateway` (161 scalars → fallback, calls == 0), `testSecondRouteCancelsFirst`.
- [ ] **Step 2: Run** `bash scripts/check_ios.sh` → compile failure.
- [ ] **Step 3: Implement** `AgentService` and the `LanternModel` wiring; keep `commandNotice` updated so V3's UI tests still pass.
- [ ] **Step 4: Run** `bash scripts/check_ios.sh` → all tests pass, including V3's `LanternUITests`.
- [ ] **Step 5: Commit** — `git commit -am "feat(app): agent routes speech through grammar then Chalk model"` (with trailer).

### Task 8: Judge view and Setup sheet

**Files:**
- Modify: `ios/Lantern/Views/LanternView.swift` — main screen per spec; move existing panels into `SetupSheet`
- Create: `ios/Lantern/Views/HoldToTalkButton.swift`
- Modify: `ios/LanternUITests/LanternUITests.swift` — open the Setup sheet (identifier `openSetup`) before the existing steps
- Test: `ios/LanternUITests/LanternUITests.swift`

**Interfaces:**
- Consumes: `LanternModel.lastTrace`, `heldTarget`, `voice.isListening/canFinish`, `model.startVoiceCommand()`, `voice.finish()`.
- Produces: identifiers `openSetup`, `holdToTalk`, `agentHeard`, `agentDid`, `agentSaid`, `statusStrip`.

- [ ] **Step 1: Write the failing UI test** `testJudgeViewShowsHeardDidSaid`: start Simulation from the Setup sheet, type `find exit` in `commandText`, tap `runCommand`, assert `agentDid` contains "find" and "grammar", `agentSaid` == "Looking for exits.".
- [ ] **Step 2: Run** `bash scripts/check_ios.sh` → the new UI test fails (identifiers missing).
- [ ] **Step 3: Implement** the layout: `VStack` with status strip (chips from `mode`, `guidanceState`, `puck.status` contains "Connected", constant "Obstacles ON"), `PuckView`, agent panel, `HoldToTalkButton` (`DragGesture(minimumDistance:0)` press → `startVoiceCommand()`, release → `voice.finish()`; `.accessibilityAction(named:"Start listening")`, `.accessibilityAction(named:"Finish")`), `Button("Setup")` presenting `.sheet` with the moved panels. `.preferredColorScheme(.dark)`, `.font(.title3)` minimum for status text.
- [ ] **Step 4: Run** `bash scripts/check_ios.sh` → all tests pass. Take a simulator screenshot into `.artifacts/judge-view.png` for the review.
- [ ] **Step 5: Commit** — `git commit -am "feat(app): judge view with hold-to-talk and setup sheet"` (with trailer).

### Task 9: Chalk routing evaluation and README

**Files:**
- Create: `chalk/evals/agent-routing.jsonl`
- Create: `chalk/feel_chalk/agent_eval.py`
- Create: `chalk/evals/validate_routing.py`
- Modify: `chalk/README.md`, `README.md` (section "Where Chalk is used")
- Test: `chalk/tests/test_agent_eval.py`

**Interfaces:**
- Consumes: `feel_chalk.agent.parse/request_body/render_context`, `feel_chalk.gateway.chat`, `chalkcompute` (as in `where_is_eval.py`).
- Produces: `chalkcompute.function route_task(utterance: str, context: str) -> str` (raw reply); scorers `tool_matches(output, expected_tool) -> float`, `args_match(output, expected_args) -> float`, `is_allowed(output) -> float`; `validate_routing.py` exits nonzero if any row is malformed or `expected_tool` is not one of the ten tools.

- [ ] **Step 1: Write the dataset.** Rows `{"utterance","language","expected_tool","expected_args"}`. Seed rows (builder adds paraphrases to reach 40, ≥4 per tool, ≥6 Spanish):
  "get me out of here" → find {"kind":"exit"}; "I need to sit down" → find {"kind":"chair"}; "where's Sarah" (teammates: Sarah) → find {"kind":"teammate"}; "is anyone around" → find {"kind":"person"}; "where's the coffee" → where_is {"thing":"coffee"}; "find the registration desk" → where_is {"thing":"registration desk"}; "call this my seat" → remember {"name":"my seat"}; "take me back to my seat" → recall {"name":"my seat"}; "take me back" → return {}; "what places do I have" → list_places {}; "never mind" → stop {}; "what's going on" → status {}; "turn off the obstacles" → none {}; "find it" → ask {}; "busca la salida" → find {"kind":"exit"}.
- [ ] **Step 2: Write the failing tests** — `test_dataset_validates` (every row parses; tool allowed; args JSON), `test_scorers` (tool/args/allowed on the shared cases: case 1 vs expected `find` → 1.0; prose → `is_allowed` 0.0).
- [ ] **Step 3: Run** `cd chalk && python3 -m unittest discover -s tests -v` → ImportError.
- [ ] **Step 4: Implement** the eval module (same shape as `where_is_eval.py`, context rendered with `render_context` defaults: en, obstacles, calibrated, puck no, places ["my seat"], teammates ["Sarah"], where_is yes) and the validator. Write the README sections: gateway for every model call, two evaluations, how to run them, that results are reported from the Chalk dashboard.
- [ ] **Step 5: Run** `cd chalk && python3 -m unittest discover -s tests -v && python3 evals/validate_routing.py evals/agent-routing.jsonl` → OK, "40 rows valid".
- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat(chalk): agent routing evaluation and README"` (with trailer).

### Task 10: Live Chalk run and device checklist (needs the key and a phone)

- [ ] **Step 1:** `cd chalk && .venv/bin/python check_connection.py --chat` → all PASS. If `BLOCKED`, stop and report what is missing.
- [ ] **Step 2:** `cd chalk && .venv/bin/python -m feel_chalk.agent_eval evals/agent-routing.jsonl` → `SUCCEEDED`; record tool accuracy, args accuracy and allowed rate in `chalk/README.md` with the run id.
- [ ] **Step 3:** Label ≥ 20 venue photos in `chalk/data/labels.jsonl`; run `.venv/bin/python -m feel_chalk.where_is_eval data/labels.jsonl`; record pointing accuracy and the not-found rate.
- [ ] **Step 4 (phone):** install on the LiDAR iPhone with `ChalkSecrets.plist` present; verify microphone and speech prompts; "find exit" offline (Wi-Fi off) → confirmation within 1 s; "where is the chair" → spoken confirmation, pin within 6 s; turn 90° → pin follows; walk to it → "You're at the chair."; cover the camera → "Lost tracking…"; "stop" → highlight off, obstacles still shown. Write results into `docs/RELEASE-STATUS.md` as PASS/FAIL/NOT RUN with the commit.
- [ ] **Step 5: Commit** the recorded results.
