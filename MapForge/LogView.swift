import SwiftUI

/// Which of its four states the Log View is in.
///
/// Four, not three. "Recording, nothing yet" is distinct from "no Session" on purpose: *am I
/// actually recording?* is the question this view exists to answer, and the two look identical
/// if they share a message — an empty pane that reads as failure.
///
/// A value rather than a tangle of `if`s inside a view, as `CommentBarState` is, and for the
/// same reason: the decision is the feature, and the drawing is not.
enum LogViewState: Equatable {
    /// There is nowhere a Session could have been written.
    case noWorkspace
    /// Nothing is recording.
    case noSession
    /// A Session is running and has recorded nothing yet.
    case recordingNothingYet
    /// The evening, as rows.
    case lines

    /// What an empty pane says, or nil when there are Lines to draw instead.
    var message: String? {
        switch self {
        case .noWorkspace: "Open a Workspace to record a Session."
        case .noSession: "No Session running — press Start Session to begin recording."
        case .recordingNothingYet: "Recording. Nothing has happened yet."
        case .lines: nil
        }
    }
}

enum LogViewPolicy {
    /// Checked outermost first: a DM with no Workspace is told about the Workspace, having
    /// not yet done the thing that makes the rest possible.
    static func state(hasWorkspace: Bool, hasSession: Bool, isEmpty: Bool) -> LogViewState {
        guard hasWorkspace else { return .noWorkspace }
        guard hasSession else { return .noSession }
        return isEmpty ? .recordingNothingYet : .lines
    }

    /// A row's height of slack, so rubber-banding does not drop following.
    static let followSlop: CGFloat = 24

    /// Whether the view should still follow the newest Line.
    ///
    /// Both measurements are taken in the ScrollView's own coordinate space: `contentMaxY` is
    /// the bottom edge of the content, and `viewportHeight` is the height of the clip it
    /// scrolls inside. At the bottom the two coincide — the content's last pixel is level with
    /// the clip's last pixel — and scrolling up pushes `contentMaxY` below the fold, past the
    /// viewport's height.
    ///
    /// The difference is what matters, never `contentMaxY` alone: it equals the viewport's
    /// height at the bottom rather than zero, so a bare `contentMaxY <= slop` is false for
    /// every log taller than its pane and following latches off exactly when it starts to
    /// matter. A content shorter than its viewport never scrolls and always follows.
    static func isFollowing(contentMaxY: CGFloat, viewportHeight: CGFloat) -> Bool {
        contentMaxY <= viewportHeight + followSlop
    }
}

/// The evening, read back: the Log View.
///
/// Takes the Map's place in the Control Window, and the Live Toolbar's with it — nothing on
/// screen here is about the Player Display. The Live Panel and the Comment Bar stay, because a
/// DM reading back over the night is the DM about to write the next Line of it.
///
/// Thin over `LogViewModel`: every ordering rule is decided there, and this draws the rows it
/// is handed in the order it is handed them. See `docs/adr/0016-the-log-view-splices-it-does-not-merge.md`.
struct LogView: View {
    let rows: [LogRow]
    let hasWorkspace: Bool
    let hasSession: Bool

    /// Whether the view is still following the newest Line.
    ///
    /// Released when the DM scrolls up and taken again when they scroll back to the bottom —
    /// the behaviour every chat app has, and the reason for it is concrete: a DM scrolled up
    /// to check Round 2 must not be yanked away by a Pawn drag, and a DM at the bottom must
    /// always see the newest.
    @State private var isFollowing = true

    /// What `scrollTo` aims at. Distinct from `scrollSpace`: one names a view to scroll to,
    /// the other the coordinate space positions are measured in.
    private static let bottomAnchor = "log-bottom"
    private static let scrollSpace = "log-scroll"

    var body: some View {
        Group {
            if let message = emptyMessage {
                empty(message)
            } else {
                log
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        .accessibilityIdentifier("log-view")
    }

    private var emptyMessage: String? {
        LogViewPolicy.state(hasWorkspace: hasWorkspace, hasSession: hasSession,
                            isEmpty: rows.isEmpty).message
    }

    private func empty(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
            .accessibilityIdentifier("log-empty")
    }

    private var log: some View {
        // The viewport's own height, which `isFollowing` measures the content against. Read
        // out here rather than inside the ScrollView: in there a GeometryReader measures the
        // content, which is the whole scrollable length and not the window onto it.
        GeometryReader { viewport in
            scrollingLog(viewportHeight: viewport.size.height)
        }
    }

    private func scrollingLog(viewportHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                // The house pattern — there is no `List` and no `Table` in this app. Rows are
                // built by hand so the indentation that carries the grouping is a property of
                // the row rather than a shape this view has to walk.
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        LogRowView(row: row)
                            .id(index)
                            // Addressed by identifier because every `staticText` in this
                            // window publishes an empty `label` on this macOS — see
                            // `.scratch/ui-tests-never-ran/`. A count is what a UI test can
                            // assert on when the words are unreachable.
                            .accessibilityIdentifier("log-row")
                    }
                    // The thing the view follows. Zero-height, so it never claims a row.
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchor)
                }
                .padding(8)
                .background(
                    // Where the content's bottom edge sits inside the clip, which is how the
                    // view learns the DM scrolled up. SwiftUI has no scroll-offset binding on
                    // macOS 15, so the position is read from the geometry instead.
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: LogScrollOffset.self,
                            value: geometry.frame(in: .named(Self.scrollSpace)).maxY)
                    })
            }
            .coordinateSpace(name: Self.scrollSpace)
            .onPreferenceChange(LogScrollOffset.self) { contentMaxY in
                isFollowing = LogViewPolicy.isFollowing(contentMaxY: contentMaxY,
                                                        viewportHeight: viewportHeight)
            }
            .onAppear { scrollToBottom(proxy) }
            .onChange(of: rows.count) { _, _ in
                guard isFollowing else { return }
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        // Deferred a runloop turn: on the first layout the anchor has no position yet, and
        // scrolling to it does nothing.
        DispatchQueue.main.async {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }
}

/// Where the content's bottom edge sits in the ScrollView's coordinate space.
///
/// `LogViewPolicy.isFollowing` is what reads it, and it needs the viewport's height to mean
/// anything — at the bottom this value *is* the viewport's height, not zero.
private struct LogScrollOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// One row. Indentation carries the grouping; colour carries what kind of thing it is.
struct LogRowView: View {
    let row: LogRow

    var body: some View {
        switch row {
        case .mapSeparator:
            separator(LogRowText.describe(row))
        case .roundHeading:
            heading(LogRowText.describe(row))
        default:
            line
        }
    }

    private var line: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let time = timestamp {
                Text(time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Text(LogRowText.describe(row))
                .font(font)
                .foregroundStyle(colour)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(row.indent) * 14)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.top, 6)
    }

    /// A Map change, drawn as the section break it is. The same treatment the Order's bench
    /// divider uses, so one list in this app does not invent a second way to break a section.
    private func separator(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider().padding(.vertical, 4)
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
        }
    }

    /// Only the Lines that carry a time show one. A Turn carries `endedAt` — when it
    /// *finished* — which is not a fact a DM wants, and ADR-0016 never compares these anyway.
    private var timestamp: String? {
        switch row {
        case let .sessionStarted(at), let .sessionEnded(at),
             let .comment(_, at), let .pawnMoved(_, _, at),
             let .savingThrow(_, _, _, at), let .abilityCheck(_, _, _, at):
            LogRowText.time(at)
        default:
            nil
        }
    }

    private var font: Font {
        switch row {
        case .turn, .liveTurn: .callout.weight(.medium)
        case .encounterStarted, .encounterEnded, .sessionStarted, .sessionEnded:
            .caption.weight(.semibold)
        default: .callout
        }
    }

    /// Problems must read as problems. An unreadable Line or an unresolvable fight is not
    /// content, and drawing it like content is how a log comes to lie quietly.
    private var colour: HierarchicalShapeStyle {
        switch row {
        case .unreadableLine, .encounterUnreadable, .orphanCorrection: .tertiary
        case .change, .correctionChange, .correction: .secondary
        case .sessionStarted, .sessionEnded, .encounterStarted, .encounterEnded: .secondary
        default: .primary
        }
    }
}
