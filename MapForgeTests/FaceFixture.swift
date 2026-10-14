import AppKit
import XCTest

/// Pictures made in memory, so no test depends on a file in the repo.
enum FaceFixture {
    enum Colour: Equatable { case red, blue, other }

    /// Red on the left half, blue on the right.
    static func halves(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image)
            .representation(using: .png, properties: [:]))
        try data.write(to: url)
    }

    static func colour(of image: CGImage, x: Int, y: Int) -> Colour {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return .other }
        if colour.redComponent > 0.9, colour.blueComponent < 0.1 { return .red }
        if colour.blueComponent > 0.9, colour.redComponent < 0.1 { return .blue }
        return .other
    }
}
