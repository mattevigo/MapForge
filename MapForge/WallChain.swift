import CoreGraphics
import Foundation

/// A polyline being traced: the vertices placed so far, and the Walls they become.
///
/// The DM draws chains because that is how a room is traced, but a Wall is a flat segment
/// (see `CONTEXT.md`) — this is where the one becomes the other. Pure state with no view
/// attached, so the click sequence can be tested without a window.
struct WallChain {
    private(set) var vertices: [MapPoint] = []

    /// Where the next span starts. The UI rubber-bands from here to the cursor, and the
    /// angle constraint measures from it.
    var lastVertex: MapPoint? { vertices.last }

    var isDrawing: Bool { !vertices.isEmpty }

    /// Add a vertex. A click on the vertex just placed is ignored — a double-click ends a
    /// chain, and its second click must not leave a zero-length Wall behind.
    mutating func place(_ point: MapPoint) {
        if let last = vertices.last, coincident(last, point) { return }
        vertices.append(point)
    }

    /// The Walls this chain describes, and reset for the next one. A chain of one vertex
    /// yields nothing: starting a chain and thinking better of it must not persist a
    /// zero-length Wall that blocks nothing and clutters the file forever.
    mutating func finish() -> [Wall] {
        defer { vertices = [] }
        guard vertices.count > 1 else { return [] }
        return (0..<(vertices.count - 1)).map {
            Wall(from: vertices[$0], to: vertices[$0 + 1])
        }
    }

    /// Discard everything. Esc means "forget this", not "keep what I have so far".
    mutating func cancel() {
        vertices = []
    }

    private func coincident(_ a: MapPoint, _ b: MapPoint) -> Bool {
        abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9
    }
}
