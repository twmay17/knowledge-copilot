/** Owns all work belonging to one playback source/position. */
export class GenerationScope {
  private controller = new AbortController();
  snapshot(): AbortSignal { return this.controller.signal; }
  isCurrent(signal: AbortSignal): boolean { return signal === this.controller.signal && !signal.aborted; }
  invalidate(): void {
    this.controller.abort();
    this.controller = new AbortController();
  }
}
