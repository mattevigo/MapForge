import AppKit

extension NSImage {
    /// True pixel dimensions of the backing representation (NSImage.size is in points).
    var pixelSize: CGSize {
        let widest = representations.max(by: { $0.pixelsWide < $1.pixelsWide })
        guard let rep = widest, rep.pixelsWide > 0 else { return size }
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }
}
