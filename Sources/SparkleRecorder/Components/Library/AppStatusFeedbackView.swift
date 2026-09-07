import SwiftUI

struct AppStatusFeedbackView: View {
    let feedback: AppStatusFeedback
    let isWindow: Bool
    let onDismiss: () -> Void

    private var accent: Color {
        switch feedback.tone {
        case .info, .progress:
            return .accentColor
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private var systemImage: String {
        switch feedback.tone {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        case .progress:
            return "clock.arrow.circlepath"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 18, height: 18)
                .padding(.top, 1)
                .accessibilityHidden(true)

            Text(verbatim: feedback.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if feedback.tone != .progress {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Dismiss", table: "Common"))
                .accessibilityLabel(String(localized: "Dismiss", table: "Common"))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: isWindow ? 480 : 350, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(accent.opacity(0.24), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 5)
        .task(id: feedback.id) {
            guard let dismissAfter = feedback.dismissAfter, dismissAfter > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(dismissAfter * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { onDismiss() }
        }
    }
}

private struct AppStatusFeedbackOverlayModifier: ViewModifier {
    @ObservedObject var state: AppState
    let isWindow: Bool
    let bottomPadding: CGFloat
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if isEnabled, let feedback = state.statusFeedback {
                AppStatusFeedbackView(
                    feedback: feedback,
                    isWindow: isWindow,
                    onDismiss: { state.dismissStatus(feedback.id) }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, bottomPadding)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.96)),
                        removal: .opacity.combined(with: .scale(scale: 0.98))
                    )
                )
                .animation(.spring(response: 0.28, dampingFraction: 0.86), value: feedback.id)
            }
        }
    }
}

extension View {
    func appStatusFeedbackOverlay(
        state: AppState,
        isWindow: Bool,
        bottomPadding: CGFloat,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            AppStatusFeedbackOverlayModifier(
                state: state,
                isWindow: isWindow,
                bottomPadding: bottomPadding,
                isEnabled: isEnabled
            )
        )
    }
}
