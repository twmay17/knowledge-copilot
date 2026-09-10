import Foundation
import os

// HISTORICAL diagnostic: compile against baseline 3063012f20e52088cd83e79f994fde44d818497d.
// The production coordinator has since been consolidated into KnowledgePackStore.
// For the current interface, run SidecastWhiteboardCoordinatorTests; this probe
// intentionally preserves the original finding rather than pretending to test the fix.

// Minimal surrounding app types; the reviewed whiteboard implementation is
// compiled directly from the working tree. All LLM calls are synthetic.
@MainActor final class AppSettings {
    enum Provider { case openRouter, ollama }
    var sidecastWhiteboardEnabled = true
    var llmProvider: Provider = .openRouter
    var openRouterApiKey = "synthetic-test-key"
}
enum Speaker { case you; var displayLabel: String { "You" } }
enum SidecastCorpusBookmark { static func resolve() -> URL? { nil } }

final class ProbeClock: Sendable {
    let storage = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_000))
    func now() -> Date { storage.withLock { $0 } }
    func advance(_ seconds: Double) { storage.withLock { $0 += seconds } }
}
final class NoteSink: Sendable {
    let storage = OSAllocatedUnfairLock(initialState: [SidecastAnsweredNote]())
    func add(_ note: SidecastAnsweredNote) { storage.withLock { $0.append(note) } }
    var count: Int { storage.withLock { $0.count } }
}
actor ProbeLLM: SidecastLLM {
    var listens = 0
    var answers = 0
    let holdListen: Bool
    let holdAnswer: Bool
    let answer: String
    var pendingListen: CheckedContinuation<String, Never>?
    var pendingAnswer: CheckedContinuation<String, Never>?
    init(holdListen: Bool = false, holdAnswer: Bool = false, answer: String = "{\"answer\":\"Synthetic unsupported fact\",\"grounded\":true,\"value\":1}") {
        self.holdListen = holdListen; self.holdAnswer = holdAnswer; self.answer = answer
    }
    func call(system: String, user: String, schema: OpenRouterClient.JSONSchemaSpec) async throws -> String {
        if schema.name == "listen_items" {
            listens += 1
            if holdListen { return await withCheckedContinuation { pendingListen = $0 } }
            return "{\"items\":[]}"
        }
        answers += 1
        if holdAnswer { return await withCheckedContinuation { pendingAnswer = $0 } }
        return answer
    }
    func releaseListen(_ raw: String = "{\"items\":[]}") { pendingListen?.resume(returning: raw); pendingListen = nil }
    func releaseAnswer() { pendingAnswer?.resume(returning: answer); pendingAnswer = nil }
}

@main struct ReviewProbe {
    static func settle() async { try? await Task.sleep(for: .milliseconds(100)) }
    @MainActor static func waitFor(_ condition: () async -> Bool) async {
        for _ in 0..<100 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
    @MainActor static func main() async throws {
        precondition(CommandLine.arguments.count == 2, "Pass a fresh temporary fixture directory")
        let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        // Invalid/no corpus must not produce an answer, including grounded=false.
        let empty = SidecastCorpusService()
        let noCorpusLLM = ProbeLLM(answer: "{\"answer\":\"Invented answer\",\"grounded\":false,\"value\":1}")
        let sink = NoteSink()
        let noCorpusOrch = SidecastQuestionOrchestrator(llm: noCorpusLLM, corpusService: empty, onNote: { sink.add($0) }, onActivity: { _, _ in })
        await noCorpusOrch.enqueue(question: "What did the deal earn?", timestamp: Date(), retrievalHint: nil)
        await settle()
        print("no_corpus_grounded_false_displayed=\(sink.count)")

        // A pass completing after new eligible utterances does not drain them.
        let clock = ProbeClock()
        let cadenceLLM = ProbeLLM(holdListen: true)
        let cadenceOrch = SidecastQuestionOrchestrator(llm: cadenceLLM, corpusService: empty, onNote: { _ in }, onActivity: { _, _ in })
        let listener = SidecastQuestionListener(orchestrator: cadenceOrch, llm: cadenceLLM, now: { clock.now() })
        await listener.noteUtterance(text: "First line", at: clock.now())
        await listener.noteUtterance(text: "Second line", at: clock.now())
        await waitFor { await cadenceLLM.listens == 1 }
        clock.advance(9)
        await listener.noteUtterance(text: "Third line", at: clock.now())
        await listener.noteUtterance(text: "What is the final number?", at: clock.now())
        await cadenceLLM.releaseListen()
        await settle()
        print("eligible_followup_after_listen_completed_listen_calls=\(await cadenceLLM.listens)")

        // Stale listener survives session transition and tags its work with new epoch.
        let sessionLLM = ProbeLLM(holdListen: true)
        let sessionSettings = AppSettings()
        let sessionCoordinator = SidecastWhiteboardCoordinator(llm: sessionLLM, settings: sessionSettings)
        sessionCoordinator.sessionStarted(at: Date())
        await settle()
        sessionCoordinator.receive(utteranceText: "Old meeting first line", speaker: .you, at: Date())
        sessionCoordinator.receive(utteranceText: "Old meeting question", speaker: .you, at: Date())
        await waitFor { await sessionLLM.listens == 1 }
        sessionCoordinator.sessionEnded()
        sessionCoordinator.sessionStarted(at: Date())
        await settle()
        await sessionLLM.releaseListen("{\"items\":[{\"question\":\"OLD SESSION PRIVATE QUESTION\"}]}")
        await settle()
        print("old_session_listener_notes_in_new_session=\(sessionCoordinator.model.notes.count)")
        sessionCoordinator.sessionEnded()

        // Provider revocation during listen is missed until the next utterance.
        let gateLLM = ProbeLLM(holdListen: true)
        let gateSettings = AppSettings()
        let gateCoordinator = SidecastWhiteboardCoordinator(llm: gateLLM, settings: gateSettings)
        gateCoordinator.sessionStarted(at: Date())
        await settle()
        gateCoordinator.receive(utteranceText: "One", speaker: .you, at: Date())
        gateCoordinator.receive(utteranceText: "Two", speaker: .you, at: Date())
        await waitFor { await gateLLM.listens == 1 }
        gateSettings.llmProvider = .ollama
        await gateLLM.releaseListen("{\"items\":[{\"question\":\"New outbound question after local switch\"}]}")
        await settle()
        print("new_answer_calls_after_provider_switched_to_local=\(await gateLLM.answers)")
        gateCoordinator.sessionEnded()

        // Lexical dedup mistakes a distinct financial period for a duplicate.
        let qa = "What was the reported RevPAR for this particular asset in 2020?"
        let qb = "What was the reported RevPAR for this particular asset in 2021?"
        let dedupLLM = ProbeLLM()
        let dedupOrch = SidecastQuestionOrchestrator(llm: dedupLLM, corpusService: empty, onNote: { _ in }, onActivity: { _, _ in })
        await dedupOrch.enqueue(question: qa, timestamp: Date(), retrievalHint: nil)
        await settle()
        await dedupOrch.enqueue(question: qb, timestamp: Date(), retrievalHint: nil)
        await settle()
        print("year_question_similarity=\(SidecastQuestionSimilarity.jaccard(qa, qb)) distinct_year_answer_calls=\(await dedupLLM.answers)")

        // Hidden-directory content is included, despite a visible corpus selection.
        let hiddenBase = base.appendingPathComponent("hidden-fixture")
        try FileManager.default.createDirectory(at: hiddenBase.appendingPathComponent(".private"), withIntermediateDirectories: true)
        try Data("SYNTHETIC HIDDEN NOTES".utf8).write(to: hiddenBase.appendingPathComponent(".private/notes.md"))
        let hiddenCorpus = SidecastCorpusService()
        let hiddenState = try await hiddenCorpus.read(folder: hiddenBase)
        print("hidden_directory_files_loaded=\(hiddenState.files.map(\.name))")

        // An oversized highest-ranking line masks even a short valid match.
        let longBase = base.appendingPathComponent("long-fixture")
        try FileManager.default.createDirectory(at: longBase, withIntermediateDirectories: true)
        try Data(String(repeating: "RevPAR ", count: 1800).utf8).write(to: longBase.appendingPathComponent("long.txt"))
        try Data("RevPAR in 2020 was $89.50.".utf8).write(to: longBase.appendingPathComponent("short.txt"))
        let longCorpus = SidecastCorpusService()
        _ = try await longCorpus.read(folder: longBase)
        print("oversized_top_chunk_evidence_is_nil=\(await longCorpus.retrieveEvidence(query: "RevPAR") == nil)")

        // A failed new-folder selection retains the previous corpus.
        do { _ = try await longCorpus.read(folder: base.appendingPathComponent("missing")) } catch {}
        print("failed_folder_switch_retains_old_corpus=\(await longCorpus.state?.folder == longBase)")

        // An answer started on A can publish after corpus B becomes active.
        let aFolder = base.appendingPathComponent("corpus-a")
        let bFolder = base.appendingPathComponent("corpus-b")
        for folder in [aFolder, bFolder] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try Data("Asset A RevPAR was $89.50.".utf8).write(to: aFolder.appendingPathComponent("facts.md"))
        try Data("Asset B RevPAR was $129.50.".utf8).write(to: bFolder.appendingPathComponent("facts.md"))
        let switchedCorpus = SidecastCorpusService()
        _ = try await switchedCorpus.read(folder: aFolder)
        let switchLLM = ProbeLLM(holdAnswer: true, answer: "{\"answer\":\"Asset A RevPAR was $89.50\",\"grounded\":true,\"value\":1}")
        let switchSink = NoteSink()
        let switchOrch = SidecastQuestionOrchestrator(llm: switchLLM, corpusService: switchedCorpus, onNote: { switchSink.add($0) }, onActivity: { _, _ in })
        await switchOrch.enqueue(question: "What was RevPAR?", timestamp: Date(), retrievalHint: nil)
        await waitFor { await switchLLM.answers == 1 }
        _ = try await switchedCorpus.read(folder: bFolder)
        await switchLLM.releaseAnswer()
        await settle()
        print("old_corpus_answers_published_after_switch=\(switchSink.count)")
    }
}
