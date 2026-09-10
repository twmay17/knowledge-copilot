import type { TranscriptSegment } from "./types.ts";

/**
 * Parses a pasted transcript into segments.
 *
 * Accepts, in order of preference:
 *   1. SRT / WebVTT cue blocks ("00:00:12,000 --> 00:00:15,000")
 *   2. Line-leading timestamps ("[01:23] text", "1:23 text", "01:02:03 text")
 *   3. Plain lines with no timing at all — durations are synthesized from
 *      word count so meeting transcripts and speaker-labelled logs still drive
 *      playback.
 *
 * Speaker labels ("Alice: ...") are preserved verbatim in the segment text,
 * which is the shape the Sidecast prompt already expects.
 */

const SPEAKING_WORDS_PER_SECOND = 2.5; // ~150 wpm
const MIN_SYNTHETIC_DURATION = 1.5;
const CUE_ARROW = "-->";

export class TranscriptParseError extends Error {}

export function parseTranscript(raw: string): TranscriptSegment[] {
  const text = raw.trim();
  if (!text) throw new TranscriptParseError("Transcript is empty");

  const segments = text.includes(CUE_ARROW)
    ? parseCueBlocks(text)
    : parseLines(text);

  if (segments.length === 0) {
    throw new TranscriptParseError("No usable lines found in transcript");
  }

  return normalize(segments);
}

// --- Format 1: SRT / WebVTT ---

function parseCueBlocks(text: string): TranscriptSegment[] {
  const segments: TranscriptSegment[] = [];
  const lines = text.split(/\r?\n/);

  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (!line.includes(CUE_ARROW)) {
      i++;
      continue;
    }

    const [rawStart, rawEnd] = line.split(CUE_ARROW).map((s) => s.trim());
    const start = parseClock(rawStart);
    if (start === null) {
      i++;
      continue;
    }
    // WebVTT cue settings ("align:start position:50%") trail the end timestamp
    const end = parseClock((rawEnd ?? "").split(/\s+/)[0] ?? "");

    // Body runs until the next blank line or the next cue
    const body: string[] = [];
    i++;
    while (i < lines.length && lines[i].trim() && !lines[i].includes(CUE_ARROW)) {
      body.push(lines[i].trim());
      i++;
    }

    const content = stripTags(body.join(" ")).trim();
    if (!content) continue;

    segments.push({
      start,
      duration: end !== null && end > start ? end - start : 0,
      text: content,
    });
  }

  return segments;
}

// --- Format 2 & 3: line-based ---

// [01:23] / [1:02:03] / 01:23 / 1:02:03, optionally followed by a separator
const LEADING_TIMESTAMP =
  /^\[?(\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d{1,3})?)\]?\s*[-–—:>|]?\s*(.*)$/;

function parseLines(text: string): TranscriptSegment[] {
  const lines = text
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l && !isNoiseLine(l));

  const timed: TranscriptSegment[] = [];
  const untimed: string[] = [];
  let sawTimestamp = false;

  for (const line of lines) {
    const match = line.match(LEADING_TIMESTAMP);
    const start = match ? parseClock(match[1]) : null;

    if (match && start !== null) {
      sawTimestamp = true;
      const content = stripTags(match[2]).trim();
      // A bare timestamp on its own line belongs to the text that follows it
      if (content) timed.push({ start, duration: 0, text: content });
      else timed.push({ start, duration: 0, text: "" });
    } else if (sawTimestamp && timed.length > 0) {
      // Continuation of the previous timed line
      const prev = timed[timed.length - 1];
      prev.text = prev.text ? `${prev.text} ${stripTags(line)}` : stripTags(line);
    } else {
      untimed.push(stripTags(line));
    }
  }

  if (sawTimestamp) {
    return timed.filter((s) => s.text.trim());
  }

  return synthesizeTimings(untimed);
}

/**
 * No timestamps anywhere — lay the lines out on a synthetic clock at natural
 * speaking pace so the harness has something to advance through.
 */
function synthesizeTimings(lines: string[]): TranscriptSegment[] {
  const segments: TranscriptSegment[] = [];
  let cursor = 0;

  for (const line of lines) {
    const words = line.split(/\s+/).filter(Boolean).length;
    const duration = Math.max(
      MIN_SYNTHETIC_DURATION,
      words / SPEAKING_WORDS_PER_SECOND
    );
    segments.push({ start: cursor, duration, text: line });
    cursor += duration;
  }

  return segments;
}

// --- Shared helpers ---

/** "01:23", "1:02:03", "00:00:12,500" -> seconds. */
function parseClock(raw: string): number | null {
  const cleaned = raw.trim().replace(",", ".");
  if (!/^\d{1,3}(:\d{1,2}){1,2}(\.\d{1,3})?$/.test(cleaned)) return null;

  const parts = cleaned.split(":").map(Number);
  if (parts.some(Number.isNaN)) return null;

  const [h, m, s] = parts.length === 3 ? parts : [0, parts[0], parts[1]];
  return h * 3600 + m * 60 + s;
}

/** SRT sequence numbers, VTT headers, and note blocks carry no content. */
function isNoiseLine(line: string): boolean {
  return (
    /^\d+$/.test(line) ||
    /^WEBVTT/i.test(line) ||
    /^NOTE(\s|$)/.test(line) ||
    /^(Kind|Language):/i.test(line)
  );
}

function stripTags(text: string): string {
  return text.replace(/<[^>]+>/g, "").replace(/\s+/g, " ");
}

/**
 * Sort by start, drop empties, and fill in any duration we could not read
 * directly from the source using the gap to the next cue.
 */
function normalize(segments: TranscriptSegment[]): TranscriptSegment[] {
  const sorted = segments
    .filter((s) => s.text.trim())
    .sort((a, b) => a.start - b.start);

  return sorted.map((seg, i) => {
    if (seg.duration > 0) return seg;

    const next = sorted[i + 1];
    const words = seg.text.split(/\s+/).filter(Boolean).length;
    const fallback = Math.max(
      MIN_SYNTHETIC_DURATION,
      words / SPEAKING_WORDS_PER_SECOND
    );

    return {
      ...seg,
      duration: next ? Math.max(0.1, next.start - seg.start) : fallback,
    };
  });
}

/** End of the last segment — the virtual player needs a stopping point. */
export function transcriptDuration(segments: TranscriptSegment[]): number {
  if (segments.length === 0) return 0;
  const last = segments[segments.length - 1];
  return last.start + last.duration;
}
