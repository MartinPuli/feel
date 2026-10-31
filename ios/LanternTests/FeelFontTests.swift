import XCTest
import UIKit
@testable import Lantern

final class FeelFontTests: XCTestCase {
    func testSelectedGeistSerifFontLoadsFromAppBundle() throws {
        let registered = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UIAppFonts") as? [String])
        XCTAssertTrue(registered.contains("GeistSerif-Regular.ttf"))
        XCTAssertNotNil(Bundle.main.url(forResource: "GeistSerif-Regular", withExtension: "ttf"))
        XCTAssertNotNil(Bundle.main.url(forResource: "OFL", withExtension: "txt"))
        XCTAssertNotNil(Bundle.main.url(forResource: "GeistSerif-NOTICE", withExtension: "txt"))

        let brand = try XCTUnwrap(UIFont(name: FeelTypography.fontName, size: 24))
        XCTAssertEqual(brand.fontName, "GeistSerif-Regular")
        XCTAssertEqual(brand.familyName, "Geist Serif")
        XCTAssertEqual(brand.pointSize, 24)
        XCTAssertEqual(FeelTypography.fontName, "GeistSerif-Regular")
    }
}
