import CoreGraphics

public enum PreviewSearchRegionHandle: Equatable, Sendable {
    case move
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

/// Pure geometry for editing a Macro Editor text-search region.
/// The caller owns visual sizing and gesture state; this Module owns the
/// invariant that the edited region respects its minimum size and remains
/// inside the optional Playback Surface bounds.
public enum PreviewSearchRegionProjector {
    public static func adjusted(
        original: CGRect,
        handle: PreviewSearchRegionHandle,
        translation: CGSize,
        bounds: CGRect?,
        minimumSize: CGSize
    ) -> CGRect {
        let minimumWidth = max(1, minimumSize.width)
        let minimumHeight = max(1, minimumSize.height)
        var minX = original.minX
        var maxX = original.maxX
        var minY = original.minY
        var maxY = original.maxY

        switch handle {
        case .move:
            minX += translation.width
            maxX += translation.width
            minY += translation.height
            maxY += translation.height
        case .topLeft:
            minX = min(original.maxX - minimumWidth, original.minX + translation.width)
            minY = min(original.maxY - minimumHeight, original.minY + translation.height)
        case .topRight:
            maxX = max(original.minX + minimumWidth, original.maxX + translation.width)
            minY = min(original.maxY - minimumHeight, original.minY + translation.height)
        case .bottomLeft:
            minX = min(original.maxX - minimumWidth, original.minX + translation.width)
            maxY = max(original.minY + minimumHeight, original.maxY + translation.height)
        case .bottomRight:
            maxX = max(original.minX + minimumWidth, original.maxX + translation.width)
            maxY = max(original.minY + minimumHeight, original.maxY + translation.height)
        }

        guard let bounds else {
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        if handle == .move {
            let width = min(maxX - minX, bounds.width)
            let height = min(maxY - minY, bounds.height)
            minX = min(max(minX, bounds.minX), bounds.maxX - width)
            minY = min(max(minY, bounds.minY), bounds.maxY - height)
            return CGRect(x: minX, y: minY, width: width, height: height)
        }

        minX = max(bounds.minX, minX)
        minY = max(bounds.minY, minY)
        maxX = min(bounds.maxX, maxX)
        maxY = min(bounds.maxY, maxY)

        let boundedMinimumWidth = min(minimumWidth, bounds.width)
        let boundedMinimumHeight = min(minimumHeight, bounds.height)
        if maxX - minX < boundedMinimumWidth {
            if handle == .topLeft || handle == .bottomLeft {
                minX = max(bounds.minX, maxX - boundedMinimumWidth)
            } else {
                maxX = min(bounds.maxX, minX + boundedMinimumWidth)
            }
        }
        if maxY - minY < boundedMinimumHeight {
            if handle == .topLeft || handle == .topRight {
                minY = max(bounds.minY, maxY - boundedMinimumHeight)
            } else {
                maxY = min(bounds.maxY, minY + boundedMinimumHeight)
            }
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
