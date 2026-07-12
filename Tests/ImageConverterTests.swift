import Foundation
import XCTest
@testable import RightClickAssistantCore

final class ImageConverterTests: XCTestCase {
    func testConvertsGrayscaleAlphaPNGToJPEG() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageConverterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let sourceURL = temporaryDirectory.appendingPathComponent("source.png")
        let sourceBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
        let sourceData = try XCTUnwrap(Data(base64Encoded: sourceBase64))
        try sourceData.write(to: sourceURL)

        let result = DefaultImageConverter().convert(url: sourceURL, toFormat: "JPEG")
        let destinationURL = try result.get()
        let destinationData = try Data(contentsOf: destinationURL)

        XCTAssertEqual(destinationURL.pathExtension, "jpg")
        XCTAssertTrue(destinationData.starts(with: Data([0xFF, 0xD8, 0xFF])))
    }
}
