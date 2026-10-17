import Foundation
import FeelCore

// Runs PointingSynthetic's scenarios through the app's real PointingDetector on the Mac,
// where Vision's barcode reader works (it doesn't in the iOS simulator).
let synthetic=PointingSynthetic()
var failures=0
for scenario in PointingSynthetic.scenarios {
    do {
        let detector=PointingDetector(); detector.useHandPoseFallback=false
        let o=detector.analyze(pixelBuffer:try synthetic.frame(for:scenario),timestamp:1)
        let problem=PointingSynthetic.check(o,scenario)
        var tip=o.fingertip.map { String(format:"tip %.2f, %.2f mm",$0.x,$0.y) } ?? "no tip"
        if let b=o.secondTip { tip+=String(format:" + %.2f, %.2f mm → column %@",b.x,b.y,o.routeColumn.map { "C\($0)" } ?? "none") }
        print("\(problem == nil ? "PASS" : "FAIL") \(scenario.name): codes \(o.codesSeen), gate \(o.gate?.reason ?? "-"), \(o.cell.map { "\($0)" } ?? "no cell"), \(tip)\(problem.map { " — \($0)" } ?? "")")
        if problem != nil { failures+=1 }
    } catch { print("FAIL \(scenario.name): \(error)"); failures+=1 }
}
print(failures == 0 ? "ALL \(PointingSynthetic.scenarios.count) SCENARIOS PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
