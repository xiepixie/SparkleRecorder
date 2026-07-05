import Cocoa
import SwiftUI
import SparkleRecorderCore

struct FlowChips: View {
    let items: [String]
    let onRemove: ((String) -> Void)?
    var onAdd: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 4) {
                ForEach(items, id: \.self) { t in
                    HStack(spacing: 4) {
                        Text(t).font(.system(size: 10, weight: .semibold))
                        if let onRemove {
                            Button { onRemove(t) } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 9))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    .onTapGesture { onAdd?(t) }
                }
            }
        }
    }
}
