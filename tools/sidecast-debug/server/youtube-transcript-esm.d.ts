// Runtime workaround for 1.3.0's mispackaged main entry. Preserve the package's
// published API types rather than declaring the deep import as `any`.
declare module "youtube-transcript/dist/youtube-transcript.esm.js" {
  export { fetchTranscript, YoutubeTranscript } from "youtube-transcript";
}
