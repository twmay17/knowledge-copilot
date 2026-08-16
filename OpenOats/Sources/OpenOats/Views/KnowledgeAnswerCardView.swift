import AppKit
import SwiftUI

struct KnowledgeAnswerCardList: View {
  enum Appearance {
    case standard
    case dark
  }

  @Bindable var store: KnowledgePackStore
  let appearance: Appearance

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if store.primaryOverlayCard != nil {
        shortcutGuide
      }

      ForEach(store.visibleOverlayCards) { card in
        KnowledgeAnswerCardView(
          card: card,
          appearance: appearance,
          isCompact: store.isOverlayCompact,
          isKeyboardTarget: store.primaryOverlayCard?.eventID == card.eventID,
          onTogglePin: { store.toggleOverlayPin(eventID: card.eventID) },
          onCopy: { copy(card.clipboardText) },
          onOpenSource: card.firstOpenableSourceURL.map { sourceURL in
            { NSWorkspace.shared.open(sourceURL) }
          },
          onToggleCompactMode: { store.toggleOverlayCompactMode() },
          onDismiss: { store.dismissOverlayCard(eventID: card.eventID) },
          onRequestCorrection: { store.requestOverlayCorrection(eventID: card.eventID) }
        )
      }
    }
  }

  private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  private var shortcutGuide: some View {
    HStack(alignment: .top, spacing: 5) {
      Image(systemName: "keyboard")
        .font(.system(size: 9, weight: .semibold))
      Text("⌥⇧⌘ · C copy · E source · P pin · W wrong · X dismiss · K compact")
        .font(.system(size: 8, weight: .medium))
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(appearance == .dark ? .white.opacity(0.55) : .secondary)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("knowledge.answer.shortcutGuide")
  }
}

private struct KnowledgeAnswerCardView: View {
  let card: KnowledgeOverlayCard
  let appearance: KnowledgeAnswerCardList.Appearance
  let isCompact: Bool
  let isKeyboardTarget: Bool
  let onTogglePin: () -> Void
  let onCopy: () -> Void
  let onOpenSource: (() -> Void)?
  let onToggleCompactMode: () -> Void
  let onDismiss: () -> Void
  let onRequestCorrection: () -> Void

  @State private var isEvidenceExpanded = false
  @State private var isCalculationExpanded = false

  private var primaryColor: Color {
    appearance == .dark ? .white : .primary
  }

  private var secondaryColor: Color {
    appearance == .dark ? .white.opacity(0.68) : .secondary
  }

  private var cardBackground: Color {
    switch appearance {
    case .standard:
      Color.accentColor.opacity(0.10)
    case .dark:
      Color.white.opacity(0.08)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      cardHeader

      cardActions

      Text(card.title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(primaryColor)
        .accessibilityIdentifier("knowledge.answer.title")

      Text(card.answer)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(primaryColor)
        .textSelection(.enabled)
        .lineLimit(isCompact ? 4 : nil)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("knowledge.answer.text")

      if !isCompact {
        trustReason

        if !card.claims.isEmpty {
          claimList
        }

        if !card.calculations.isEmpty {
          calculationDisclosure
        }

        if !card.sources.isEmpty {
          evidenceDisclosure
        }
      }

      if card.isCorrectionRequested {
        Label("Marked for correction review", systemImage: "checkmark.circle")
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(secondaryColor)
          .accessibilityIdentifier("knowledge.answer.correctionRequested")
      }
    }
    .padding(isCompact ? 9 : 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(cardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(evidenceColor.opacity(0.34), lineWidth: 1)
    }
    .opacity(card.isSuperseded ? 0.68 : 1)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("knowledge.answer.card")
  }

  private var cardHeader: some View {
    HStack(alignment: .top, spacing: 6) {
      evidenceBadge

      if card.isProvisional {
        statusBadge("Checking", icon: "clock")
      }
      if card.isPinned {
        statusBadge(card.isSuperseded ? "Pinned snapshot" : "Pinned", icon: "pin.fill")
      }
      if isKeyboardTarget {
        statusBadge("Shortcut target", icon: "keyboard")
      }

      Spacer(minLength: 4)

      actionButton(
        icon: "xmark",
        label: shortcutLabel("Dismiss answer", .dismiss),
        action: onDismiss
      )
    }
  }

  private var cardActions: some View {
    HStack(spacing: 5) {
      if let onOpenSource {
        actionButton(
          icon: "doc.text.magnifyingglass",
          label: shortcutLabel("Open first source", .openSource),
          action: onOpenSource
        )
        .accessibilityIdentifier("knowledge.answer.openFirstSource")
      }
      actionButton(
        icon: "doc.on.doc",
        label: shortcutLabel("Copy answer and sources", .copyAnswer),
        action: onCopy
      )
      .accessibilityIdentifier("knowledge.answer.copy")
      if isKeyboardTarget {
        actionButton(
          icon: isCompact ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
          label: shortcutLabel(
            isCompact ? "Use full answer view" : "Use compact answer view",
            .toggleCompactMode
          ),
          action: onToggleCompactMode
        )
        .accessibilityIdentifier("knowledge.answer.compactMode")
      }

      Spacer(minLength: 4)

      actionButton(
        icon: card.isPinned ? "pin.slash" : "pin",
        label: shortcutLabel(card.isPinned ? "Unpin answer" : "Pin answer", .togglePin),
        action: onTogglePin
      )
      actionButton(
        icon: "pencil.and.list.clipboard",
        label: shortcutLabel("Mark answer for correction", .requestCorrection),
        action: onRequestCorrection
      )
    }
    .accessibilityIdentifier("knowledge.answer.actions")
  }

  private var trustReason: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("Why")
        .font(.system(size: 9, weight: .bold))
        .textCase(.uppercase)
      Text(card.why)
        .font(.system(size: 10))
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(secondaryColor)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("knowledge.answer.why")
  }

  private var claimList: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(card.evidenceState == .contested ? "Attributed claims" : "Corpus claim")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(secondaryColor)

      ForEach(card.claims) { claim in
        VStack(alignment: .leading, spacing: 2) {
          Text(claim.value)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(primaryColor)
          if !claim.context.isEmpty {
            Text(claim.context)
              .font(.system(size: 9, design: .monospaced))
              .foregroundStyle(secondaryColor)
          }
          if !claim.attribution.isEmpty {
            Text(claim.attribution)
              .font(.system(size: 9))
              .foregroundStyle(secondaryColor)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(evidenceColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 5))
      }
    }
    .accessibilityIdentifier("knowledge.answer.claims")
  }

  private var calculationDisclosure: some View {
    DisclosureGroup(isExpanded: $isCalculationExpanded) {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(card.calculations) { calculation in
          VStack(alignment: .leading, spacing: 3) {
            Label("\(calculation.name) · v\(calculation.version)", systemImage: "function")
              .font(.system(size: 10, weight: .medium))
            Text(calculation.expression)
              .font(.system(size: 10, design: .monospaced))
            ForEach(calculation.inputs) { input in
              VStack(alignment: .leading, spacing: 1) {
                Text(calculationValueLabel(input))
                  .font(.system(size: 10, design: .monospaced))
                if !input.citations.isEmpty {
                  Text("Source: " + input.citations.map(sourceLabel).joined(separator: ", "))
                    .font(.system(size: 9))
                }
              }
            }
            if let output = calculation.output {
              Text("Result · \(calculationValueLabel(output))")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
          }
        }
      }
      .padding(.top, 5)
    } label: {
      Label("Calculation details (\(card.calculations.count))", systemImage: "function")
        .font(.system(size: 10, weight: .semibold))
    }
    .foregroundStyle(secondaryColor)
    .accessibilityIdentifier("knowledge.answer.calculation")
  }

  private var evidenceDisclosure: some View {
    DisclosureGroup(isExpanded: $isEvidenceExpanded) {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(card.sources) { source in
          sourceView(source)
        }
      }
      .padding(.top, 5)
    } label: {
      Label("Evidence (\(card.sources.count))", systemImage: "doc.text.magnifyingglass")
        .font(.system(size: 10, weight: .semibold))
    }
    .foregroundStyle(secondaryColor)
    .accessibilityIdentifier("knowledge.answer.evidence")
  }

  @ViewBuilder
  private func sourceView(_ source: KnowledgeOverlaySource) -> some View {
    let content = VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 5) {
        Text(source.title)
          .font(.system(size: 10, weight: .medium))
        if source.fileURL != nil {
          Image(systemName: "arrow.up.forward.app")
            .font(.system(size: 8))
        }
      }
      if !source.locator.isEmpty {
        Text(source.locator)
          .font(.system(size: 9))
      }
      if let attribution = source.attribution, !attribution.isEmpty {
        Text(attribution)
          .font(.system(size: 9, weight: .medium))
      }
      if !source.excerpt.isEmpty {
        Text(source.excerpt)
          .font(.system(size: 9))
          .lineLimit(6)
          .textSelection(.enabled)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())

    if let fileURL = source.fileURL {
      Button {
        NSWorkspace.shared.open(fileURL)
      } label: {
        content
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Open evidence: \(source.title), \(source.locator)")
      .accessibilityIdentifier("knowledge.answer.source.\(source.id)")
    } else {
      content
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("knowledge.answer.source.\(source.id)")
    }
  }

  private var evidenceBadge: some View {
    Label(card.evidenceLabel, systemImage: evidenceIcon)
      .font(.system(size: 9, weight: .semibold))
      .foregroundStyle(evidenceColor)
      .lineLimit(1)
      .minimumScaleFactor(0.75)
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(Capsule().fill(evidenceColor.opacity(0.12)))
      .accessibilityLabel("Evidence state: \(card.evidenceLabel). \(card.evidenceExplanation)")
      .accessibilityIdentifier("knowledge.answer.evidenceState")
  }

  private func statusBadge(_ label: String, icon: String) -> some View {
    Label(label, systemImage: icon)
      .font(.system(size: 8, weight: .medium))
      .foregroundStyle(secondaryColor)
      .lineLimit(1)
  }

  private func shortcutLabel(
    _ label: String,
    _ command: KnowledgeOverlayCommand
  ) -> String {
    guard isKeyboardTarget else { return label }
    return "\(label) (\(command.shortcutLabel))"
  }

  private func actionButton(
    icon: String,
    label: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 9, weight: .semibold))
        .frame(width: 18, height: 18)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(secondaryColor)
    .help(label)
    .accessibilityLabel(label)
  }

  private var evidenceIcon: String {
    switch card.evidenceState {
    case .directlySourced, .supportedByCorpus: "checkmark.seal.fill"
    case .calculated: "function"
    case .contradictedByCorpus, .contested: "exclamationmark.triangle.fill"
    case .interpretive: "text.bubble"
    case .notFoundInCorpus: "questionmark.folder"
    case .needsClarification: "questionmark.bubble"
    }
  }

  private var evidenceColor: Color {
    switch card.evidenceState {
    case .directlySourced, .calculated, .supportedByCorpus: .green
    case .contradictedByCorpus, .contested: .orange
    case .interpretive: .blue
    case .notFoundInCorpus, .needsClarification: .yellow
    }
  }

  private func calculationLabel(_ predicate: String) -> String {
    predicate.split(separator: ".").last.map(String.init)?
      .replacingOccurrences(of: "_", with: " ") ?? predicate
  }

  private func calculationValueLabel(_ value: KnowledgeCalculationValueSummary) -> String {
    let context = value.qualifiers.sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
      .joined(separator: ", ")
    let suffix = context.isEmpty ? "" : " · \(context)"
    return "\(calculationLabel(value.predicate)): \(value.displayValue)\(suffix)"
  }

  private func sourceLabel(_ citation: KnowledgeEvidenceCitation) -> String {
    guard !citation.locatorLabel.isEmpty else { return citation.sourceTitle }
    return "\(citation.sourceTitle) · \(citation.locatorLabel)"
  }
}
