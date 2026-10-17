import XCTest
import FeelCore
@testable import Lantern

@MainActor
final class AdvancedCoordinatorTests:XCTestCase {
    func command(_ text:String,_ model:LanternModel) { model.commandText=text; model.submitTypedCommand() }
    func testTypedCommandsUseMemoryAndPreserveObstacleBands() {
        let model=LanternModel(); defer { model.stop() }
        model.startSimulation(memory:true)
        command("remember Lab",model); XCTAssertEqual(model.spatialMemory.bookmarks.first?.name,"Lab")
        model.simulateMove(metres:-2); command("recall Lab",model)
        XCTAssertEqual(model.packet.highlight,3); XCTAssertEqual(model.packet.bands[2],1)
        model.adaptiveProfile = .reduced
        XCTAssertEqual(model.packet.highlight,255); XCTAssertEqual(model.packet.bands[2],1); XCTAssertEqual(model.packet.bands[3],3)
        command("list places",model); XCTAssertTrue(model.commandNotice.contains("Lab"))
        command("stop",model); XCTAssertEqual(model.mode,.stopped); XCTAssertEqual(model.packet.bands,Array(repeating:0,count:7))
    }
    func testSpanishCommandsAndRejectedCompositeDoNotChangeSelection() {
        let model=LanternModel(); defer { model.stop() }
        model.startSimulation(memory:true); model.commandLanguage = .es
        command("recuerda Mesa",model); XCTAssertEqual(model.spatialMemory.bookmarks.first?.name,"Mesa")
        command("busca código",model); XCTAssertEqual(model.finder,.barcode)
        command("para; busca persona",model)
        XCTAssertEqual(model.mode,.simulation); XCTAssertEqual(model.finder,.barcode)
        XCTAssertEqual(model.spatialMemory.bookmarks.count,1)
    }
    func testSimulationCannotSaveOrLoadARealWorldMap() {
        let model=LanternModel(); defer { model.stop() }
        model.startSimulation(memory:true); model.saveMap()
        XCTAssertFalse(model.mapBusy); XCTAssertTrue(model.mapNotice.contains("live session"))
        model.loadMap(); XCTAssertEqual(model.restoreState,.idle); XCTAssertEqual(model.mode,.simulation)
        XCTAssertFalse(model.localVoice.isListening)
    }
    func testGlobalMuteAlsoSilencesLocalCommandReadback() {
        let model = LanternModel(voice: RealtimeVoiceSession(speaksLocally: false))
        defer { model.stop() }
        model.voice.setSpokenOutput(false)
        let initial = model.localVoice.status
        model.readCommandResult()
        XCTAssertEqual(model.localVoice.status, initial)
        XCTAssertFalse(model.localVoice.isListening)
        XCTAssertFalse(model.voice.spokenOutputEnabled)
    }

    func testStopCancelsVoiceAndClearsRestoreState() {
        let model=LanternModel(); model.startSimulation(memory:true); model.stop()
        XCTAssertFalse(model.localVoice.isListening); XCTAssertEqual(model.restoreState,.idle)
        XCTAssertFalse(model.restoredMapSession); XCTAssertFalse(model.mapBusy)
    }
}
