import { fetchTranscript } from "youtube-transcript/dist/youtube-transcript.esm.js";

export interface TranscriptSegment {
  start: number;
  duration: number;
  text: string;
}

/** Explicitly mirrors the two XML branches in pinned youtube-transcript 1.3.0.
 * Never infer units from magnitude: early millisecond offsets can be small too.
 */
export function captionTimeUnit(xml: string): "milliseconds" | "seconds" | undefined {
  if (/<p\s+t="\d+"\s+d="\d+"[^>]*>[\s\S]*?<\/p>/.test(xml)) return "milliseconds";
  if (/<text start="[^"]*" dur="[^"]*">[^<]*<\/text>/.test(xml)) return "seconds";
  return undefined;
}

export async function fetchTranscriptSeconds(videoID: string, transport: typeof fetch = fetch): Promise<TranscriptSegment[]> {
  if (!/^[A-Za-z0-9_-]{11}$/.test(videoID)) throw new Error("Invalid video ID");
  let unit: ReturnType<typeof captionTimeUnit>;
  const deadline = AbortSignal.timeout(15_000);
  const captureFormat: typeof fetch = async (input, options) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    const response = await transport(input, { ...options, signal: deadline });
    // The package requests the selected track from YouTube's timedtext endpoint.
    // An unsupported endpoint/format fails closed below instead of guessing.
    if (url.hostname.endsWith(".youtube.com") && url.pathname === "/api/timedtext" && response.ok) {
      unit = captionTimeUnit(await response.clone().text());
    }
    return response;
  };
  const raw = await fetchTranscript(videoID, { lang: "en", fetch: captureFormat });
  if (raw.length === 0) return [];
  if (!unit) throw new Error("Unsupported caption timing format");
  const divisor = unit === "milliseconds" ? 1000 : 1;
  const segments = raw.map(entry => ({ start: entry.offset / divisor, duration: entry.duration / divisor, text: entry.text }));
  if (segments.some(s => !Number.isFinite(s.start) || s.start < 0 || !Number.isFinite(s.duration) || s.duration < 0)) {
    throw new Error("Invalid caption timing");
  }
  return segments.sort((a, b) => a.start - b.start);
}
