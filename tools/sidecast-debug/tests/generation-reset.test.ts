import assert from "node:assert/strict";
import test from "node:test";
import { GenerationScope } from "../src/generation-scope.ts";
import { ensureSummary, getSummary, resetSummary } from "../src/transcript.ts";
import { clearState, generate, getMessages } from "../src/sidecast.ts";
import type { AppSettings } from "../src/types.ts";

const settings: AppSettings = {
  llmProvider: "ollama", apiKey: "", baseURL: "http://127.0.0.1:11434", model: "synthetic",
  temperature: 0, maxTokens: 100, windowSize: 1, summaryRefreshInterval: 1,
  intensity: "balanced", systemPromptTemplate: "Synthetic", minValueThreshold: 0,
  webSearchEngine: "auto", webSearchMaxResults: 0, personas: [],
};

test("source/seek invalidation aborts old requests without invalidating the replacement", () => {
  const scope = new GenerationScope();
  const old = scope.snapshot();
  scope.invalidate();
  assert.equal(old.aborted, true);
  assert.equal(scope.isCurrent(old), false);
  assert.equal(scope.isCurrent(scope.snapshot()), true);
});

test("old summary cannot restore text or clear a newer in-flight summary after reset", async () => {
  resetSummary();
  const segments = [0, 1, 2].map(start => ({ start, duration: 1, text: "Synthetic" }));
  let releaseOld!: (value: string) => void;
  let releaseNew!: (value: string) => void;
  const old = ensureSummary(segments, 3, settings, () => new Promise(resolve => { releaseOld = resolve; }));
  resetSummary();
  const next = ensureSummary(segments, 3, settings, () => new Promise(resolve => { releaseNew = resolve; }));
  releaseOld("OLD PRIVATE SUMMARY");
  await old;
  assert.equal(getSummary(), "");
  let unexpected = false;
  await ensureSummary(segments, 3, settings, async () => { unexpected = true; return "BAD"; });
  assert.equal(unexpected, false);
  releaseNew("NEW SUMMARY");
  await next;
  assert.equal(getSummary(), "NEW SUMMARY");
  resetSummary();
});

test("clearing generation aborts its transport and rejects even an abort-ignoring stale response", async () => {
  const originalFetch = globalThis.fetch;
  let signal: AbortSignal | undefined;
  let release!: (response: Response) => void;
  globalThis.fetch = async (_input, options) => {
    signal = options?.signal ?? undefined;
    return await new Promise(resolve => { release = resolve; });
  };
  try {
    clearState();
    const result = generate({ latestUtterance: "Old", recentExchange: "Old", widerContext: "Old", conversationSummary: "Old" }, 0, settings);
    const rejected = assert.rejects(result, { name: "AbortError" });
    clearState();
    assert.equal(signal?.aborted, true);
    release(Response.json({ choices: [{ message: { content: '{"messages":[]}' } }] }));
    await rejected;
    assert.deepEqual(getMessages(), []);
  } finally {
    globalThis.fetch = originalFetch;
    clearState();
  }
});
