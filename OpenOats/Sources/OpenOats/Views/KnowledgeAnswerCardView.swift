import AppKit
import SwiftUI

struct KnowledgeAnswerCardList: View {
  enum Appearance {
    case standard
    case dark
  }

  @Bindable var store: KnowledgePackStore
  let appearance: Appearance

  private var cards: [KnowledgeAnswerCard] {
    store.activeAnswerCards.sorted { lhs, rhs in
      if lhs.key == "remote" { return true }
      if rhs.key == "remote" { return false }
      return lhs.key < rhs.key
    }.map(\.value)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(cards) { card in
        KnowledgeAnswerCardView(card: card, appearance: appearance)
      }
    }
  }
}

private struct KnowledgeAnswerCardView: View {
  let card: KnowledgeAnswerCard
  let appearance: KnowledgeAnswerCardList.Appearance

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
      Text(card.title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(primaryColor)
        .accessibilityIdentifier("knowledge.answer.title")

      Text(card.answer)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(primaryColor)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("knowledge.answer.text")

      evidenceBadge

      if !card.calculations.isEmpty {
        VStack(alignment: .leading, spacing: 3) {
          ForEach(card.calculations) { calculation in
            Label("\(calculation.name) · v\(calculation.version)", systemImage: "function")
              .font(.system(size: 10, weight: .medium))
            Text(calculation.expression)
              .font(.system(size: 10, design: .monospaced))
            ForEach(calculation.inputs) { input in
              VStack(alignment: .leading, spacing: 1) {
                Text(calculationValueLabel(input))
                  .font(.system(size: 10, design: .monospaced))
                if !input.citations.isEmpty {
                  Text(
                    "Source: "
                      + input.citations.map(sourceLabel).joined(separator: ", ")
                  )
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
        .foregroundStyle(secondaryColor)
        .accessibilityIdentifier("knowledge.answer.calculation")
      }

      if !card.citations.isEmpty {
        VStack(alignment: .leading, spacing: 5) {
          Text("Evidence")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(secondaryColor)

          ForEach(card.citations) { citation in
            Button {
              NSWorkspace.shared.open(citation.fileURL)
            } label: {
              HStack(alignment: .top, spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                  .font(.system(size: 10))
                  .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                  Text(citation.sourceTitle)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                  if !citation.locatorLabel.isEmpty {
                    Text(citation.locatorLabel)
                      .font(.system(size: 9))
                      .lineLimit(2)
                  }
                }
                Spacer(minLength: 2)
                Image(systemName: "arrow.up.forward.app")
                  .font(.system(size: 9))
              }
              .foregroundStyle(secondaryColor)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(citation.excerpt)
            .accessibilityLabel("Open evidence: \(citation.sourceTitle), \(citation.locatorLabel)")
            .accessibilityIdentifier("knowledge.answer.evidence.\(citation.passageID)")
          }
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(cardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(evidenceColor.opacity(0.28), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("knowledge.answer.card")
  }

  private var evidenceBadge: some View {
    Label(evidenceLabel, systemImage: evidenceIcon)
      .font(.system(size: 9, weight: .semibold))
      .foregroundStyle(evidenceColor)
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(Capsule().fill(evidenceColor.opacity(0.12)))
      .accessibilityIdentifier("knowledge.answer.evidenceState")
  }

  private var evidenceLabel: String {
    switch card.evidenceState {
    case .directlySourced: "Direct source"
    case .calculated: "Calculated"
    case .supportedByCorpus: "Corpus supported"
    case .contradictedByCorpus: "Contradicted"
    case .contested: "Contested"
    case .interpretive: "Interpretive"
    case .notFoundInCorpus: "Not found"
    case .needsClarification: "Clarify"
    }
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
