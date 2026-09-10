import Foundation

/// Inventory, not a prediction of recall/accuracy on arbitrary conversation.
struct WhiteboardPackReadiness: Equatable, Sendable {
  let totalQuestionFamilies: Int
  let reviewedQuestionFamilies: Int
  let knownGaps: Int
  let disagreements: Int
  let cardsAwaitingReview: Int

  init(pack: KnowledgePack) {
    let reviewed = pack.responseCards.filter { $0.reviewStatus == .reviewed }
    totalQuestionFamilies = pack.questionFamilies.count
    reviewedQuestionFamilies = Set(reviewed.flatMap(\.questionFamilyIDs)).count
    knownGaps =
      reviewed.filter {
        $0.evidenceState == .notFoundInCorpus || $0.evidenceState == .needsClarification
      }.count
    disagreements = reviewed.filter { $0.evidenceState == .contested }.count
    cardsAwaitingReview = pack.responseCards.filter { $0.reviewStatus == .generated }.count
  }

  var summary: String {
    "\(reviewedQuestionFamilies)/\(totalQuestionFamilies) question families reviewed · \(knownGaps) known gaps · \(disagreements) disagreements · \(cardsAwaitingReview) cards awaiting review"
  }
}
