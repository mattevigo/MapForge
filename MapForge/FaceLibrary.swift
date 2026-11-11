import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The Workspace's kept Faces: the squares the DM cut, in `.mapforge/faces/`, one PNG each.
///
/// Writes a cut once, under a fresh name, and never rewrites or deletes one — a Face is a
/// copy (ADR-0007, ADR-0028), so two Pawns may share a file and neither may change under the
/// other. A file no Pawn uses any more is litter, not damage, and removing it loses nothing.
final class FaceLibrary {
    /// The side a kept cut is scaled down to when it is larger. A token is never drawn more
    /// than a few hundred points across, so more pixels than this are weight in the Workspace
    /// and nothing on the screen. A smaller cut is kept as it is, never scaled up.
    static let keptSide = 512

    let directory: URL
    private let cache = NSCache<NSString, NSImage>()

    init(directory: URL) {
        self.directory = directory
    }

    /// Cuts `cut` out of `picture`, keeps the square, and returns the Face that names it.
    ///
    /// `cut` is in the picture's pixels, top-left origin, as `FaceCut` makes it.
    func keep(_ picture: CGImage, cut: CGRect) throws -> PawnFace {
        guard let square = picture.cropping(to: cut.integral) else { throw KeepError.cutOutside }
        let kept = square.width > Self.keptSide ? try scaled(square) : square

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = "\(UUID().uuidString).png"
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil) else { throw KeepError.encoding }
        CGImageDestinationAddImage(destination, kept, nil)
        guard CGImageDestinationFinalize(destination) else { throw KeepError.encoding }
        try (data as Data).write(to: directory.appendingPathComponent(file), options: .atomic)
        return PawnFace(file: file, origin: .hand)
    }

    /// Whether the cut named `file` is kept here.
    func holds(_ file: String) -> Bool {
        url(of: file).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// Where the cut named `file` is kept — or nil for a name that is not one.
    ///
    /// A name and only a name: the fog file and the roster are the DM's to edit by hand, and a
    /// `file` that reaches out of the folder is refused rather than followed.
    private func url(of file: String) -> URL? {
        guard !file.isEmpty, !file.hasPrefix("."), !file.contains("/") else { return nil }
        return directory.appendingPathComponent(file)
    }

    /// The kept cut `face` names, or nil when there is none — the Pawn is then drawn in its
    /// colour and is otherwise in no way diminished.
    func image(for face: PawnFace) -> NSImage? {
        let name = face.file
        guard let url = url(of: name) else { return nil }
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    private func scaled(_ square: CGImage) throws -> CGImage {
        let side = Self.keptSide
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw KeepError.encoding
        }
        context.interpolationQuality = .high
        context.draw(square, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let image = context.makeImage() else { throw KeepError.encoding }
        return image
    }

    enum KeepError: Error {
        case cutOutside
        case encoding
    }
}

/// Reading a picture the DM picked, in the orientation it is meant to be seen in.
enum FacePicture {
    /// The picture types a Face can be cut from: the ones a Map accepts.
    static let types: [UTType] = [.png, .jpeg, .webP]

    /// The picture at `url`, its camera rotation applied, or nil when it is not one.
    ///
    /// Through ImageIO's thumbnail path at full size rather than `NSImage`, because that is
    /// what applies a photo's EXIF orientation — a portrait taken on a phone would otherwise
    /// be cut lying on its side — and it gives the pixel size the cut is measured in.
    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                  as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

private struct FaceLibraryKey: EnvironmentKey {
    static let defaultValue: FaceLibrary? = nil
}

extension EnvironmentValues {
    /// Where `PawnToken` finds a Face's kept cut. Nil with no Workspace open, when every Pawn
    /// is drawn in its colour.
    var faceLibrary: FaceLibrary? {
        get { self[FaceLibraryKey.self] }
        set { self[FaceLibraryKey.self] = newValue }
    }
}
