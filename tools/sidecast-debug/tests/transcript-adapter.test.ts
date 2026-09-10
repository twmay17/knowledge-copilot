import assert from "node:assert/strict";
import test from "node:test";
import { captionTimeUnit, fetchTranscriptSeconds } from "../server/transcript-adapter.ts";

function transportFor(xml: string): typeof fetch {
  return async (input) => {
    const url = new URL(String(input));
    if (url.pathname === "/youtubei/v1/player") {
      return Response.json({ captions: { playerCaptionsTracklistRenderer: { captionTracks: [
        { languageCode: "en", baseUrl: "https://www.youtube.com/api/timedtext?v=abcdefghijk" },
      ] } } });
    }
    assert.equal(url.pathname, "/api/timedtext", "No unexpected network request");
    return new Response(xml);
  };
}

test("legacy seconds and srv3 milliseconds produce the same 120-second segment", async () => {
  const legacy = await fetchTranscriptSeconds("abcdefghijk", transportFor('<transcript><text start="120" dur="2">A &amp; B</text></transcript>'));
  const srv3 = await fetchTranscriptSeconds("abcdefghijk", transportFor('<timedtext><p t="120000" d="2000">A &amp; B</p></timedtext>'));
  assert.deepEqual(legacy, [{ start: 120, duration: 2, text: "A & B" }]);
  assert.deepEqual(srv3, legacy);
});

test("small millisecond offsets are not guessed to be seconds", async () => {
  const result = await fetchTranscriptSeconds("abcdefghijk", transportFor('<p t="50" d="100">Test</p>'));
  assert.equal(result[0].start, 0.05);
  assert.equal(result[0].duration, 0.1);
  assert.equal(captionTimeUnit("unsupported"), undefined);
});

test("invalid values and video IDs fail closed", async () => {
  await assert.rejects(fetchTranscriptSeconds("abcdefghijk", transportFor('<text start="NaN" dur="2">Bad</text>')), /Invalid caption timing/);
  await assert.rejects(fetchTranscriptSeconds("https://untrusted.example/", async () => { throw new Error("must not fetch"); }), /Invalid video ID/);
});
