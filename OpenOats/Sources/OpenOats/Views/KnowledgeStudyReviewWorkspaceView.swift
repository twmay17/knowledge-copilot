import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct KnowledgeStudyReviewWorkspaceView: View {
  @Environment(KnowledgePackStore.self) private var knowledgePackStore
  @Environment(\.openSettings) private var openSettings
  @State private var model: KnowledgeStudyReviewWorkspaceModel?
  @State private var showApplyConfirmation = false

  var body: some View {
    Group {
      if let model {
        workspace(model)
      } else {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .task {
      guard model == nil else { return }
      model = KnowledgeStudyReviewWorkspaceModel(
        profileRegistry: knowledgePackStore.profileRegistry,
        reviewer: normalizedSystemReviewer
      )
    }
    .onChange(of: knowledgePackStore.selectedPackDirectory) {
      model?.clear()
    }
    .alert(
      "Review Error",
      isPresented: Binding(
        get: { model?.errorMessage != nil },
        set: { isPresented in
          if !isPresented { model?.dismissError() }
        }
      )
    ) {
      Button("OK") { model?.dismissError() }
    } message: {
      Text(model?.errorMessage ?? "The review operation failed.")
    }
    .alert("Apply reviewed import?", isPresented: $showApplyConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Apply to Pack") {
        guard let model else { return }
        Task {
          if await model.applyImport() {
            await knowledgePackStore.reload()
          }
        }
      }
    } message: {
      Text(
        "This writes the explicitly approved question families and response cards to the active KnowledgePack. The base hash will be checked again under an exclusive lock before any file changes."
      )
    }
  }

  @ViewBuilder
  private func workspace(_ model: KnowledgeStudyReviewWorkspaceModel) -> some View {
    VStack(spacing: 0) {
      header(model)
      Divider()

      if knowledgePackStore.selectedPackDirectory == nil {
        ContentUnavailableView {
          Label("Select a KnowledgePack", systemImage: "shippingbox")
        } description: {
          Text(
            "Choose and validate a KnowledgePack before opening a frontier-analysis review queue.")
        } actions: {
          Button("Open Settings") { openSettings() }
        }
      } else if !model.isLoaded {
        ContentUnavailableView {
          Label("Load a Review Queue", systemImage: "checklist")
        } description: {
          Text(
            "Open a pending review queue created from the exact active corpus. The queue is revalidated locally before anything is shown."
          )
        } actions: {
          Button("Choose Review Queue…") { chooseQueue(for: model) }
            .buttonStyle(.borderedProminent)
            .disabled(model.activity != .idle)
        }
      } else {
        reviewPanes(model)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func header(_ model: KnowledgeStudyReviewWorkspaceModel) -> some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Knowledge Review")
          .font(.system(size: 16, weight: .semibold))
        Text(headerSubtitle(model))
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      if model.activity != .idle {
        ProgressView()
          .controlSize(.small)
      }

      if knowledgePackStore.selectedPackDirectory != nil {
        Button(model.isLoaded ? "Open Another Queue…" : "Choose Review Queue…") {
          chooseQueue(for: model)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(model.activity != .idle)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 11)
  }

  private func reviewPanes(_ model: KnowledgeStudyReviewWorkspaceModel) -> some View {
    HStack(spacing: 0) {
      reviewSidebar(model)
        .frame(minWidth: 245, idealWidth: 270, maxWidth: 310)

      Divider()

      reviewDetail(model)
        .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)

      Divider()

      reviewSummary(model)
        .frame(width: 300)
    }
  }

  private func reviewSidebar(_ model: KnowledgeStudyReviewWorkspaceModel) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 14) {
        reviewSidebarSection(
          "Question families", selections: model.questionSelections, model: model)
        reviewSidebarSection(
          "Response cards", selections: model.responseCardSelections, model: model)

        if !model.contradictionSelections.isEmpty || !model.corpusGapSelections.isEmpty {
          Divider()
          reviewSidebarSection(
            "Contradictions", selections: model.contradictionSelections, model: model)
          reviewSidebarSection("Corpus gaps", selections: model.corpusGapSelections, model: model)
        }
      }
      .padding(12)
    }
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
  }

  @ViewBuilder
  private func reviewSidebarSection(
    _ title: String,
    selections: [KnowledgeStudyReviewWorkspaceSelection],
    model: KnowledgeStudyReviewWorkspaceModel
  ) -> some View {
    if !selections.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Text(title.uppercased())
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.secondary)

        ForEach(selections) { selection in
          reviewSidebarRow(selection, model: model)
        }
      }
    }
  }

  private func reviewSidebarRow(
    _ selection: KnowledgeStudyReviewWorkspaceSelection,
    model: KnowledgeStudyReviewWorkspaceModel
  ) -> some View {
    let isSelected = model.selection == selection
    return Button {
      model.selection = selection
    } label: {
      HStack(spacing: 8) {
        Image(systemName: sidebarIcon(for: selection))
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(sidebarIconColor(for: selection, model: model))
          .frame(width: 16)

        Text(selectionTitle(selection, model: model))
          .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
          .foregroundStyle(.primary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)

        Spacer(minLength: 4)

        if let disposition = model.draft(for: selection)?.disposition {
          Image(systemName: disposition == .approve ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(disposition == .approve ? .green : .red)
        } else if model.draft(for: selection) != nil {
          Circle()
            .stroke(.tertiary, lineWidth: 1)
            .frame(width: 10, height: 10)
        }
      }
      .padding(.horizontal, 9)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
        in: RoundedRectangle(cornerRadius: 7)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("knowledgeReview.sidebar.\(selection.id)")
  }

  @ViewBuilder
  private func reviewDetail(_ model: KnowledgeStudyReviewWorkspaceModel) -> some View {
    if let selection = model.selection {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          switch selection {
          case .questionFamily(let id):
            if let proposal = model.queue?.analysis.questionFamilyProposals.first(where: {
              $0.id == id
            }) {
              questionDetail(proposal)
            }
          case .responseCard(let id):
            if let item = model.queue?.responseCardItems.first(where: { $0.id == id }) {
              responseCardDetail(item)
            }
          case .contradiction(let id):
            if let contradiction = model.queue?.analysis.contradictions.first(where: {
              $0.id == id
            }) {
              contradictionDetail(contradiction, model: model)
            }
          case .corpusGap(let id):
            if let gap = model.queue?.analysis.corpusGaps.first(where: { $0.id == id }) {
              corpusGapDetail(gap)
            }
          }

          if model.draft(for: selection) != nil {
            decisionEditor(selection, model: model)
          }
        }
        .padding(20)
        .frame(maxWidth: 860, alignment: .leading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else {
      ContentUnavailableView("Select a review item", systemImage: "checklist")
    }
  }

  private func questionDetail(_ proposal: KnowledgeStudyQuestionFamilyProposal) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      detailTitle("Question family", title: proposal.canonicalQuestion, icon: "questionmark.bubble")
      stringListSection("Variants", values: proposal.variants)
      stringListSection("Early speech prefixes", values: proposal.partialPrefixes)
      stringListSection("Aliases", values: proposal.aliases)
      stringListSection("Tags", values: proposal.tags)
    }
  }

  private func responseCardDetail(_ item: KnowledgeStudyResponseCardReviewItem) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      detailTitle("Presenter response", title: item.proposal.title, icon: "text.bubble")

      HStack(spacing: 8) {
        evidenceStateBadge(item.proposal.evidenceState)
        Label("Generated — not yet trusted", systemImage: "sparkles")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.orange)
      }

      reviewSection("Proposed answer") {
        Text(item.proposal.answer)
          .font(.system(size: 15))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      if let caveat = item.proposal.caveat {
        reviewSection("Caveat") {
          Label(caveat, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
            .textSelection(.enabled)
        }
      }

      if !item.referencedAssertions.isEmpty {
        reviewSection("Assertions") {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(item.referencedAssertions) { assertion in
              assertionRow(assertion)
            }
          }
        }
      }

      if !item.citedPassages.isEmpty {
        reviewSection("Exact cited passages") {
          VStack(alignment: .leading, spacing: 12) {
            ForEach(item.citedPassages) { passage in
              passageRow(passage)
            }
          }
        }
      }

      if !item.referencedCalculations.isEmpty {
        reviewSection("Registered calculations") {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(item.referencedCalculations) { calculation in
              calculationRow(calculation)
            }
          }
        }
      }
    }
  }

  private func contradictionDetail(
    _ contradiction: KnowledgeStudyContradictionProposal,
    model: KnowledgeStudyReviewWorkspaceModel
  ) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      detailTitle("Corpus finding", title: "Contradiction", icon: "arrow.left.arrow.right")
      reviewSection("Finding") {
        Text(contradiction.summary)
          .font(.system(size: 15))
          .textSelection(.enabled)
      }

      let assertions =
        model.bundle?.assertions.filter {
          contradiction.assertionIDs.contains($0.id)
        } ?? []
      if !assertions.isEmpty {
        reviewSection("Conflicting assertions") {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(assertions) { assertion in assertionRow(assertion) }
          }
        }
      }

      let passages =
        model.bundle?.citedPassages.filter {
          contradiction.citationPassageIDs.contains($0.id)
        } ?? []
      if !passages.isEmpty {
        reviewSection("Cited passages") {
          VStack(alignment: .leading, spacing: 12) {
            ForEach(passages) { passage in passageRow(passage) }
          }
        }
      }

      findingNotice(
        "This finding is context for the reviewer. It is not imported as a response card unless a separate card proposal is explicitly approved."
      )
    }
  }

  private func corpusGapDetail(_ gap: KnowledgeStudyCorpusGapProposal) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      detailTitle("Corpus finding", title: gap.question, icon: "questionmark.folder")
      reviewSection("Why the corpus is insufficient") {
        Text(gap.detail)
          .font(.system(size: 15))
          .textSelection(.enabled)
      }
      findingNotice(
        "A corpus gap cannot be approved into a factual answer. Add or correct source material, rebuild the Study Bundle, and run preparation again."
      )
    }
  }

  private func decisionEditor(
    _ selection: KnowledgeStudyReviewWorkspaceSelection,
    model: KnowledgeStudyReviewWorkspaceModel
  ) -> some View {
    let draft = model.draft(for: selection) ?? .init()
    return reviewSection("Human decision") {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
          decisionButton(
            "Approve",
            systemImage: "checkmark.circle.fill",
            color: .green,
            isSelected: draft.disposition == .approve
          ) {
            model.setDisposition(.approve, for: selection)
          }
          decisionButton(
            "Reject",
            systemImage: "xmark.circle.fill",
            color: .red,
            isSelected: draft.disposition == .reject
          ) {
            model.setDisposition(.reject, for: selection)
          }
          Spacer()
        }

        Text("Reviewer note (optional)")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
        TextEditor(
          text: Binding(
            get: { model.draft(for: selection)?.note ?? "" },
            set: { model.setNote($0, for: selection) }
          )
        )
        .font(.system(size: 12))
        .frame(minHeight: 64, maxHeight: 100)
        .padding(5)
        .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
          RoundedRectangle(cornerRadius: 6).stroke(.quaternary)
        }
        .disabled(model.receipt != nil)
      }
    }
  }

  private func reviewSummary(_ model: KnowledgeStudyReviewWorkspaceModel) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Review progress")
            .font(.system(size: 14, weight: .semibold))
          Text("Every proposal needs an explicit decision.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }

        HStack(spacing: 8) {
          countBadge("Pending", value: model.pendingCount, color: .orange)
          countBadge("Approve", value: model.approvedCount, color: .green)
          countBadge("Reject", value: model.rejectedCount, color: .red)
        }

        Divider()

        VStack(alignment: .leading, spacing: 6) {
          Text("Named reviewer")
            .font(.system(size: 11, weight: .semibold))
          TextField(
            "Full name",
            text: Binding(
              get: { model.reviewer },
              set: { model.updateReviewer($0) }
            )
          )
          .textFieldStyle(.roundedBorder)
          .disabled(model.receipt != nil)
        }

        if let blocker = model.preparationBlocker, model.importPlan == nil {
          Label(blocker, systemImage: "info.circle")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }

        Button {
          Task { _ = await model.prepareImport() }
        } label: {
          Label("Preview Import", systemImage: "doc.text.magnifyingglass")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.canPrepareImport)
        .accessibilityIdentifier("knowledgeReview.previewImport")

        if let plan = model.importPlan {
          Divider()
          importPlanSummary(plan, model: model)

          Button {
            showApplyConfirmation = true
          } label: {
            Label(applyButtonTitle(plan), systemImage: "square.and.arrow.down")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .tint(.green)
          .disabled(!model.canApplyImport)
          .accessibilityIdentifier("knowledgeReview.applyImport")
        }

        if let receipt = model.receipt {
          Divider()
          receiptSummary(receipt)
        }

        Spacer(minLength: 0)
      }
      .padding(16)
    }
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
  }

  private func importPlanSummary(
    _ plan: KnowledgeStudyImportPlan,
    model: KnowledgeStudyReviewWorkspaceModel
  ) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      Label("Validated import plan", systemImage: "checkmark.shield.fill")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.green)
      summaryRow("State", value: plan.state.rawValue.replacingOccurrences(of: "_", with: " "))
      summaryRow("Questions", value: "\(plan.approvedQuestionFamilyIDs.count)")
      summaryRow("Cards", value: "\(plan.approvedResponseCardIDs.count)")
      summaryRow("Rejected", value: "\(plan.rejectedProposalCount)")
      VStack(alignment: .leading, spacing: 2) {
        Text("Resulting corpus hash")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(.secondary)
        Text(plan.resultingPackContentHash)
          .font(.system(size: 9, design: .monospaced))
          .textSelection(.enabled)
          .lineLimit(2)
      }
    }
  }

  private func receiptSummary(_ receipt: KnowledgeStudyImportReceipt) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(
        "Import \(receipt.outcome.rawValue.replacingOccurrences(of: "_", with: " "))",
        systemImage: "checkmark.seal.fill"
      )
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(.green)
      Text("The active pack was reloaded and is ready for live use.")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      Text(receipt.resultingPackContentHash)
        .font(.system(size: 9, design: .monospaced))
        .textSelection(.enabled)
    }
  }

  private func detailTitle(_ eyebrow: String, title: String, icon: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(Color.accentColor)
        .frame(width: 28, height: 28)
      VStack(alignment: .leading, spacing: 3) {
        Text(eyebrow.uppercased())
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.secondary)
        Text(title)
          .font(.system(size: 22, weight: .semibold))
          .textSelection(.enabled)
      }
    }
  }

  private func stringListSection(_ title: String, values: [String]) -> some View {
    reviewSection(title) {
      if values.isEmpty {
        Text("None")
          .foregroundStyle(.tertiary)
      } else {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(values, id: \.self) { value in
            Label(value, systemImage: "circle.fill")
              .labelStyle(ReviewBulletLabelStyle())
              .textSelection(.enabled)
          }
        }
      }
    }
  }

  private func assertionRow(_ assertion: KnowledgeStudyAssertion) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("\(assertion.subject) · \(assertion.predicate)")
          .font(.system(size: 11, weight: .semibold))
        Spacer()
        Text(assertion.kind.rawValue)
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(.secondary)
      }
      Text(formattedValue(assertion.value))
        .font(.system(size: 13, weight: .medium))
        .textSelection(.enabled)
      if !assertion.qualifiers.isEmpty {
        Text(
          assertion.qualifiers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(
            separator: " · ")
        )
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
      }
    }
    .padding(10)
    .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
  }

  private func passageRow(_ passage: KnowledgeStudyPassage) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Label(passage.sourceTitle, systemImage: "doc.text")
          .font(.system(size: 11, weight: .semibold))
        Spacer()
        Text(locatorText(passage.locator))
          .font(.system(size: 9))
          .foregroundStyle(.secondary)
      }
      Text(passage.excerpt)
        .font(.system(size: 12))
        .textSelection(.enabled)
      Text(passage.sourceRelativePath)
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(.tertiary)
        .textSelection(.enabled)
    }
    .padding(10)
    .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
  }

  private func calculationRow(_ calculation: KnowledgeCalculation) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("\(calculation.name) · v\(calculation.version)")
        .font(.system(size: 11, weight: .semibold))
      Text(calculation.expression)
        .font(.system(size: 11, design: .monospaced))
        .textSelection(.enabled)
      Text("Inputs: \(calculation.inputAssertionIDs.joined(separator: ", "))")
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
    .padding(10)
    .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
  }

  private func evidenceStateBadge(_ state: KnowledgeEvidenceState) -> some View {
    Text(state.rawValue.replacingOccurrences(of: "_", with: " "))
      .font(.system(size: 10, weight: .semibold))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Color.accentColor.opacity(0.13), in: Capsule())
  }

  private func findingNotice(_ text: String) -> some View {
    Label(text, systemImage: "info.circle")
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
      .padding(12)
      .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
  }

  private func decisionButton(
    _ title: String,
    systemImage: String,
    color: Color,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }
    .buttonStyle(.bordered)
    .tint(isSelected ? color : .secondary)
  }

  private func countBadge(_ title: String, value: Int, color: Color) -> some View {
    VStack(spacing: 2) {
      Text("\(value)")
        .font(.system(size: 16, weight: .bold))
      Text(title)
        .font(.system(size: 9, weight: .medium))
    }
    .foregroundStyle(value > 0 ? color : .secondary)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .background(color.opacity(value > 0 ? 0.09 : 0.03), in: RoundedRectangle(cornerRadius: 7))
  }

  private func summaryRow(_ title: String, value: String) -> some View {
    HStack {
      Text(title)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .fontWeight(.medium)
    }
    .font(.system(size: 11))
  }

  @ViewBuilder
  private func reviewSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
      content()
    }
    .padding(13)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(nsColor: .controlBackgroundColor).opacity(0.48), in: RoundedRectangle(cornerRadius: 9)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 9).stroke(.quaternary)
    }
  }

  private func chooseQueue(for model: KnowledgeStudyReviewWorkspaceModel) {
    guard let packDirectory = knowledgePackStore.selectedPackDirectory else { return }
    let panel = NSOpenPanel()
    panel.title = "Choose Pending Study Review Queue"
    panel.message = "Select the validated review-queue JSON created for the active KnowledgePack."
    panel.prompt = "Open Queue"
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true

    guard panel.runModal() == .OK, let queueURL = panel.url else { return }
    Task { _ = await model.load(queueURL: queueURL, packDirectory: packDirectory) }
  }

  private func headerSubtitle(_ model: KnowledgeStudyReviewWorkspaceModel) -> String {
    if model.isLoaded {
      return "\(model.packTitle) · \(model.queue?.queueID ?? "pending queue")"
    }
    switch knowledgePackStore.state {
    case .loaded(_, let summary): return summary.title
    case .loading: return "Loading active KnowledgePack…"
    case .failed(_, let message): return message
    case .idle: return "No active KnowledgePack"
    }
  }

  private func selectionTitle(
    _ selection: KnowledgeStudyReviewWorkspaceSelection,
    model: KnowledgeStudyReviewWorkspaceModel
  ) -> String {
    switch selection {
    case .questionFamily(let id):
      return model.queue?.analysis.questionFamilyProposals.first { $0.id == id }?.canonicalQuestion
        ?? id
    case .responseCard(let id):
      return model.queue?.analysis.responseCardProposals.first { $0.id == id }?.title ?? id
    case .contradiction(let id):
      return model.queue?.analysis.contradictions.first { $0.id == id }?.summary ?? id
    case .corpusGap(let id):
      return model.queue?.analysis.corpusGaps.first { $0.id == id }?.question ?? id
    }
  }

  private func sidebarIcon(for selection: KnowledgeStudyReviewWorkspaceSelection) -> String {
    switch selection {
    case .questionFamily: return "questionmark.bubble"
    case .responseCard: return "text.bubble"
    case .contradiction: return "arrow.left.arrow.right"
    case .corpusGap: return "questionmark.folder"
    }
  }

  private func sidebarIconColor(
    for selection: KnowledgeStudyReviewWorkspaceSelection,
    model: KnowledgeStudyReviewWorkspaceModel
  ) -> Color {
    if let disposition = model.draft(for: selection)?.disposition {
      return disposition == .approve ? .green : .red
    }
    switch selection {
    case .contradiction: return .orange
    case .corpusGap: return .yellow
    case .questionFamily, .responseCard: return .secondary
    }
  }

  private func formattedValue(_ value: KnowledgeValue) -> String {
    let base: String
    switch value.type {
    case .text: base = value.text ?? "—"
    case .number:
      base = value.number?.formatted(.number.precision(.fractionLength(0...4))) ?? "—"
    case .boolean: base = value.boolean.map { $0 ? "true" : "false" } ?? "—"
    case .date: base = value.date ?? "—"
    case .reference: base = value.referenceID ?? "—"
    }
    return value.unit.map { "\(base) \($0)" } ?? base
  }

  private func locatorText(_ locator: KnowledgeSourceLocator) -> String {
    var parts: [String] = []
    if let page = locator.page { parts.append("page \(page)") }
    if let sheet = locator.sheet { parts.append(sheet) }
    if let range = locator.cellRange { parts.append(range) }
    if !locator.sectionPath.isEmpty { parts.append(locator.sectionPath.joined(separator: " › ")) }
    return parts.isEmpty ? "source excerpt" : parts.joined(separator: " · ")
  }

  private func applyButtonTitle(_ plan: KnowledgeStudyImportPlan) -> String {
    switch plan.state {
    case .ready: return "Apply Reviewed Import…"
    case .alreadyApplied: return "Confirm Existing Import…"
    case .noChanges: return "Record No Changes…"
    }
  }

  private var normalizedSystemReviewer: String {
    let name = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
    return name.count <= 200 ? name : ""
  }
}

private struct ReviewBulletLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 7) {
      configuration.icon
        .font(.system(size: 4))
        .foregroundStyle(.tertiary)
      configuration.title
        .font(.system(size: 12))
    }
  }
}
