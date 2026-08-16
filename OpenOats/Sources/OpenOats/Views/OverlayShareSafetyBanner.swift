import SwiftUI

struct OverlayShareSafetyBanner: View {
  enum Appearance {
    case standard
    case dark
  }

  let hideFromScreenShare: Bool
  let appearance: Appearance

  private var notice: KnowledgeOverlayShareSafetyNotice {
    KnowledgeOverlayShareSafetyNotice.make(hideFromScreenShare: hideFromScreenShare)
  }

  private var foregroundColor: Color {
    appearance == .dark ? .white.opacity(0.88) : .primary
  }

  private var secondaryColor: Color {
    appearance == .dark ? .white.opacity(0.66) : .secondary
  }

  private var accentColor: Color {
    notice.severity == .warning ? .red : .orange
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "rectangle.on.rectangle.badge.exclamationmark")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(accentColor)

      VStack(alignment: .leading, spacing: 2) {
        Text(notice.title)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(foregroundColor)
        Text(notice.message)
          .font(.system(size: 9))
          .foregroundStyle(secondaryColor)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(accentColor.opacity(appearance == .dark ? 0.16 : 0.10))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("overlay.screenShareWarning")
  }
}
