import express from "express";
import { fetchTranscriptSeconds } from "./transcript-adapter.js";

const app = express();
const PORT = 3001;

// Vite proxies same-origin requests. Do not expose transcripts cross-origin.

app.get("/api/transcript", async (req, res) => {
  const videoId = req.query.v;
  if (typeof videoId !== "string" || !/^[A-Za-z0-9_-]{11}$/.test(videoId)) {
    res.status(400).json({ error: "Provide an 11-character video ID in ?v=" });
    return;
  }

  try {
    const segments = await fetchTranscriptSeconds(videoId);
    console.log(`[transcript-proxy] ${videoId}: ${segments.length} segments`);
    res.json({ segments });
  } catch (err: any) {
    console.error(`[transcript-proxy] ${err.message}`);
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, "127.0.0.1", () => {
  console.log(`[transcript-proxy] listening on http://localhost:${PORT}`);
});
