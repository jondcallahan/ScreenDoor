import SwiftUI

/// The fold across iPhone Duo's inner display, in a view's own coordinates.
struct Fold: Equatable {
    var frame: CGRect
    /// False while the device lies flat. The fold is still there, but nothing needs to avoid it.
    var isActive: Bool

    /// The crease runs top to bottom, like a book's spine.
    var isVertical: Bool { frame.height > frame.width }

    /// Folded with the crease across the middle, propped up like a laptop. The top half faces you
    /// and the bottom half lies on the table.
    var isTabletop: Bool { isActive && !isVertical }
}

extension GeometryProxy {
    /// The fold that crosses this view, or nil on devices without one.
    /// - Parameter includeFlat: Also return the fold while the device lies flat. Use this for layout
    ///   that should stay the same whether or not the device is folded.
    func fold(includeFlat: Bool = false) -> Fold? {
        #if os(iOS)
        guard #available(iOS 27.1, *) else { return nil }
        let regions = reservedRegions(kind: .division, options: includeFlat ? .includeInactive : [])
        // A flat fold has no width, so check its centre line rather than whether it overlaps.
        let region = regions.first { region in
            let frame = region.frame
            return frame.height > frame.width
                ? frame.midX > 0 && frame.midX < size.width
                : frame.midY > 0 && frame.midY < size.height
        }
        return region.map { Fold(frame: $0.frame, isActive: $0.isActive) }
        #else
        return nil
        #endif
    }
}

extension View {
    /// Moves content to one side of the fold while the device is folded: the trailing side when
    /// it's folded like a book, and the top half when it's propped up like a laptop.
    func avoidsFold() -> some View {
        modifier(AvoidsFold())
    }
}

private struct AvoidsFold: ViewModifier {
    @State private var fold: Fold?
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(insets)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: Fold?.self) { $0.fold() } action: { fold = $0 }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .animation(.smooth, value: fold)
    }

    private var insets: EdgeInsets {
        guard let fold, fold.isActive else { return EdgeInsets() }
        return fold.isVertical
            ? EdgeInsets(top: 0, leading: fold.frame.maxX, bottom: 0, trailing: 0)
            : EdgeInsets(top: 0, leading: 0, bottom: max(0, size.height - fold.frame.minY), trailing: 0)
    }
}

/// Reads iPhone Duo's hinge angle. Nil on devices without a hinge, before iOS 27.1, and on Vision Pro.
struct HingeAngleReader: ViewModifier {
    @Binding var angle: Double?

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, new in angle = new.hinge?.angle.radians }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
