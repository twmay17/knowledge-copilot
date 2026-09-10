import type {
  TranscriptSegment,
  AppSettings,
  DebugLogEntry,
  PlaybackSource,
} from "./types.ts";
import { YouTubePlayer, extractVideoId } from "./player.ts";
import { VirtualPlayer } from "./virtual-player.ts";
import { GenerationScope } from "./generation-scope.ts";
import {
  parseTranscript,
  transcriptDuration,
  TranscriptParseError,
} from "./paste.ts";
import {
  fetchTranscript,
  findActiveSegmentIndex,
  buildContextWindow,
  ensureSummary,
  resetSummary,
} from "./transcript.ts";
import { loadSettings, saveSettings } from "./settings.ts";
import {
  generate,
  getMessages,
  clearState,
  llmCall,
} from "./sidecast.ts";
import {
  renderSettingsPanel,
  renderTranscriptViewer,
  renderSidecastBubbles,
  renderDebugLog,
  setStatus,
} from "./ui.ts";

let settings: AppSettings = loadSettings();
let segments: TranscriptSegment[] = [];
let lastTriggeredSegmentIndex = -1;
let lastGeneratedSegmentIndex = -1;
let isGenerating = false;
const requestScope = new GenerationScope();
let debugLog: DebugLogEntry[] = [];
let debugLogCounter = 0;

const MIN_NEW_SEGMENTS_BEFORE_GENERATION = 10;

// --- Render settings panel ---
function refreshSettings() {
  renderSettingsPanel(
    document.getElementById("settings-panel")!,
    settings,
    (updated) => {
      settings = updated;
      refreshSettings(); // Re-render on structural changes (persona add/remove)
    }
  );
}
refreshSettings();

// --- Playback sources ---
const player = new YouTubePlayer(
  "yt-player-container",
  (time) => { if (activeSource === player) onTimeUpdate(time); },
  (time) => { if (activeSource === player) onSeek(time); }
);

const virtualPlayer = new VirtualPlayer(
  (time) => { if (activeSource === virtualPlayer) onTimeUpdate(time); },
  (time) => { if (activeSource === virtualPlayer) onSeek(time); },
  (playing) => {
    (document.getElementById("vp-play") as HTMLButtonElement).textContent =
      playing ? "Pause" : "Play";
  }
);

// Whichever clock is currently driving the harness
let activeSource: PlaybackSource = player;

/** Wipe generation state so a new transcript starts from a clean slate. */
function resetForNewTranscript() {
  requestScope.invalidate();
  isGenerating = false;
  clearState();
  resetSummary();
  lastTriggeredSegmentIndex = -1;
  lastGeneratedSegmentIndex = -1;
  segments = [];
  debugLog = [];
  debugLogCounter = 0;
  document.getElementById("sidecast-bubbles")!.innerHTML = "";
  document.getElementById("debug-log")!.innerHTML = "";
}

// --- URL loading ---
document.getElementById("yt-load")!.addEventListener("click", loadVideo);
document.getElementById("yt-url")!.addEventListener("keydown", (e) => {
  if ((e as KeyboardEvent).key === "Enter") loadVideo();
});

async function loadVideo() {
  const url = (document.getElementById("yt-url") as HTMLInputElement).value;
  const videoId = extractVideoId(url);
  if (!videoId) {
    setStatus("error", "Invalid YouTube URL");
    return;
  }

  setStatus("loading", "Loading video and transcript...");
  virtualPlayer.pause();
  activeSource = player;
  document.getElementById("virtual-transport")!.hidden = true;
  resetForNewTranscript();

  const request = requestScope.snapshot();
  try {
    const [, transcriptSegments] = await Promise.all([
      player.loadVideo(videoId),
      fetchTranscript(videoId, request),
    ]);
    if (!requestScope.isCurrent(request)) return;
    segments = transcriptSegments;
    renderTranscriptViewer(
      document.getElementById("transcript-viewer")!,
      segments,
      -1,
      (time) => activeSource.seekTo(time)
    );
    setStatus("ok", `Loaded ${segments.length} transcript segments`);
  } catch (err: any) {
    if (requestScope.isCurrent(request)) setStatus("error", err.message);
  }
}

// --- Pasted transcript ---
const pasteToggle = document.getElementById("paste-toggle")!;
const pastePanel = document.getElementById("paste-panel")!;
const pasteInput = document.getElementById("paste-input") as HTMLTextAreaElement;
const pasteHint = document.getElementById("paste-hint")!;
const transport = document.getElementById("virtual-transport")!;
const scrub = document.getElementById("vp-scrub") as HTMLInputElement;
const timeLabel = document.getElementById("vp-time")!;

pasteToggle.addEventListener("click", () => {
  pastePanel.hidden = !pastePanel.hidden;
  pasteToggle.classList.toggle("open", !pastePanel.hidden);
  if (!pastePanel.hidden) pasteInput.focus();
});

document.getElementById("paste-load")!.addEventListener("click", loadPastedTranscript);
document.getElementById("paste-clear")!.addEventListener("click", () => {
  pasteInput.value = "";
  pasteHint.textContent = "";
  pasteInput.focus();
});

// Cmd+Enter loads without reaching for the mouse
pasteInput.addEventListener("keydown", (e) => {
  const ev = e as KeyboardEvent;
  if (ev.key === "Enter" && (ev.metaKey || ev.ctrlKey)) loadPastedTranscript();
});

function loadPastedTranscript() {
  let parsed: TranscriptSegment[];
  try {
    parsed = parseTranscript(pasteInput.value);
  } catch (err: any) {
    const message =
      err instanceof TranscriptParseError ? err.message : "Could not parse transcript";
    pasteHint.textContent = message;
    setStatus("error", message);
    return;
  }

  // The pasted transcript takes over the clock — silence the video
  player.stop();
  activeSource = virtualPlayer;

  resetForNewTranscript();
  segments = parsed;

  const duration = transcriptDuration(segments);
  virtualPlayer.load(duration);
  scrub.max = String(Math.ceil(duration));
  scrub.value = "0";
  transport.hidden = false;
  updateTransportLabel(0);

  renderTranscriptViewer(
    document.getElementById("transcript-viewer")!,
    segments,
    -1,
    (time) => activeSource.seekTo(time)
  );

  pasteHint.textContent = `${segments.length} segments · ${formatClock(duration)}`;
  setStatus("ok", `Loaded ${segments.length} pasted segments — press Play`);
}

// --- Virtual transport controls ---
document.getElementById("vp-play")!.addEventListener("click", () => {
  virtualPlayer.toggle();
});

// Track the label while dragging, but only seek on release — "input" fires
// continuously and every seek kicks off a generation.
scrub.addEventListener("input", () => {
  updateTransportLabel(Number(scrub.value));
});

scrub.addEventListener("change", () => {
  virtualPlayer.seekTo(Number(scrub.value));
});

document.getElementById("vp-speed")!.addEventListener("change", (e) => {
  virtualPlayer.setSpeed(Number((e.target as HTMLSelectElement).value));
});

/** Keep the scrubber and clock in step while the virtual player is driving. */
function syncTransport(currentTime: number) {
  if (activeSource !== virtualPlayer) return;
  scrub.value = String(Math.floor(currentTime));
  updateTransportLabel(currentTime);
}

function updateTransportLabel(currentTime: number) {
  timeLabel.textContent = `${formatClock(currentTime)} / ${formatClock(
    virtualPlayer.getDuration()
  )}`;
}

function formatClock(seconds: number): string {
  const total = Math.max(0, Math.floor(seconds));
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

// --- Playback callbacks ---
function onTimeUpdate(currentTime: number) {
  if (segments.length === 0) return;
  syncTransport(currentTime);

  const idx = findActiveSegmentIndex(segments, currentTime);
  renderTranscriptViewer(
    document.getElementById("transcript-viewer")!,
    segments,
    idx,
    (time) => activeSource.seekTo(time)
  );

  // Trigger sidecast when enough new segments have accumulated
  if (idx > lastTriggeredSegmentIndex && idx >= 0) {
    lastTriggeredSegmentIndex = idx;
    const newSegsSinceLastGen = idx - lastGeneratedSegmentIndex;
    if (newSegsSinceLastGen >= MIN_NEW_SEGMENTS_BEFORE_GENERATION) {
      triggerSidecast(currentTime);
    }
  }
}

function onSeek(currentTime: number) {
  if (segments.length === 0) return;
  requestScope.invalidate();
  clearState();
  isGenerating = false;
  syncTransport(currentTime);

  const idx = findActiveSegmentIndex(segments, currentTime);
  lastTriggeredSegmentIndex = idx;

  // Seeks always invalidate the summary — it will rebuild for the new position
  resetSummary();

  renderTranscriptViewer(
    document.getElementById("transcript-viewer")!,
    segments,
    idx,
    (time) => activeSource.seekTo(time)
  );

  triggerSidecast(currentTime);
}

// --- Sidecast generation ---
async function triggerSidecast(currentTime: number) {
  if (isGenerating) return;
  const request = requestScope.snapshot();
  isGenerating = true;
  setStatus("loading", "Generating sidecast...");

  try {
    // If video hasn't started, use a small offset so the first segment is included
    const effectiveTime = currentTime < 0.5 && segments.length > 0
      ? segments[0].start + 0.01
      : currentTime;

    // Ensure summary covers content before the rolling window
    await ensureSummary(segments, effectiveTime, settings, (sys, usr) =>
      llmCall(sys, usr, settings, request)
    );
    if (!requestScope.isCurrent(request)) return;

    const context = buildContextWindow(segments, effectiveTime, settings);
    if (!context.latestUtterance) {
      setStatus("ok", "No transcript content at current position");
      isGenerating = false;
      return;
    }

    const result = await generate(context, effectiveTime, settings, request);
    if (!requestScope.isCurrent(request)) return;

    // Cooldown skip — keep the existing bubbles and log intact
    if (result.skipped) {
      setStatus("ok", "Cooldown — waiting");
      isGenerating = false;
      return;
    }

    // Track that a real generation happened at this segment
    lastGeneratedSegmentIndex = lastTriggeredSegmentIndex;

    // Add to debug history
    debugLog.push({
      id: ++debugLogCounter,
      timestamp: effectiveTime,
      wallTime: new Date(),
      result,
    });
    renderDebugLog(document.getElementById("debug-log")!, debugLog);

    // Render output
    renderSidecastBubbles(
      document.getElementById("sidecast-bubbles")!,
      getMessages(),
      settings.personas
    );

    if (result.accepted.length > 0 || result.filtered.length > 0) {
      setStatus("ok", `Generated: ${result.accepted.length} shown, ${result.filtered.length} filtered`);
    } else {
      setStatus("ok", "No new sidecast output");
    }
  } catch (err: any) {
    if (!requestScope.isCurrent(request)) return;
    console.error("[sidecast] generation error:", err);
    setStatus("error", `Generation failed: ${err.message}`);
  } finally {
    if (requestScope.isCurrent(request)) isGenerating = false;
  }
}

// --- Manual controls ---
document.getElementById("generate-btn")!.addEventListener("click", () => {
  const currentTime = activeSource.getCurrentTime();
  triggerSidecast(currentTime);
});

document.getElementById("clear-btn")!.addEventListener("click", () => {
  clearState();
  debugLog = [];
  debugLogCounter = 0;
  document.getElementById("sidecast-bubbles")!.innerHTML = "";
  document.getElementById("debug-log")!.innerHTML = "";
  setStatus("ok", "Cleared");
});

// --- Demo mode toggle ---
const demoBtn = document.getElementById("demo-btn")!;
const expandIcon = `<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="10 2 14 2 14 6"/><polyline points="6 14 2 14 2 10"/><polyline points="14 10 14 14 10 14"/><polyline points="2 6 2 2 6 2"/></svg>`;
const collapseIcon = `<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 14 4 10 0 10"/><polyline points="12 2 12 6 16 6"/><polyline points="0 6 4 6 4 2"/><polyline points="16 10 12 10 12 14"/></svg>`;
demoBtn.addEventListener("click", () => {
  const app = document.getElementById("app")!;
  const isDemo = app.classList.toggle("demo-mode");
  demoBtn.innerHTML = isDemo ? collapseIcon : expandIcon;
});
