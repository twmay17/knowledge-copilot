import type { PlaybackSource } from "./types.ts";

type PlayerCallback = (currentTime: number) => void;

/**
 * Drives the harness from a pasted transcript with no video attached.
 *
 * Emits the same one-virtual-second cadence as YouTubePlayer's poll loop, so
 * main.ts cannot tell the two apart. Playback speed shortens the wall-clock
 * interval rather than the virtual step, which keeps segment timing honest
 * while letting a long transcript be run through quickly.
 */
export class VirtualPlayer implements PlaybackSource {
  private currentTime = 0;
  private duration = 0;
  private speed = 1;
  private tickInterval: number | null = null;
  private onTimeUpdate: PlayerCallback;
  private onSeek: PlayerCallback;
  private onStateChange: (playing: boolean) => void;

  constructor(
    onTimeUpdate: PlayerCallback,
    onSeek: PlayerCallback,
    onStateChange: (playing: boolean) => void = () => {}
  ) {
    this.onTimeUpdate = onTimeUpdate;
    this.onSeek = onSeek;
    this.onStateChange = onStateChange;
  }

  load(duration: number): void {
    // pause(), not stop() — the play button label has to fall back to "Play"
    this.pause();
    this.duration = duration;
    this.currentTime = 0;
  }

  getCurrentTime(): number {
    return this.currentTime;
  }

  getDuration(): number {
    return this.duration;
  }

  isPlaying(): boolean {
    return this.tickInterval !== null;
  }

  seekTo(seconds: number): void {
    this.currentTime = clamp(seconds, 0, this.duration);
    this.onSeek(this.currentTime);
  }

  play(): void {
    if (this.tickInterval !== null) return;
    if (this.currentTime >= this.duration) this.currentTime = 0;

    this.tickInterval = window.setInterval(() => this.tick(), 1000 / this.speed);
    this.onStateChange(true);
  }

  pause(): void {
    this.stop();
    this.onStateChange(false);
  }

  toggle(): void {
    this.isPlaying() ? this.pause() : this.play();
  }

  setSpeed(speed: number): void {
    this.speed = speed;
    // Restart the timer so the new interval takes effect immediately
    if (this.isPlaying()) {
      this.stop();
      this.tickInterval = window.setInterval(() => this.tick(), 1000 / this.speed);
    }
  }

  stop(): void {
    if (this.tickInterval !== null) {
      clearInterval(this.tickInterval);
      this.tickInterval = null;
    }
  }

  private tick(): void {
    this.currentTime = Math.min(this.currentTime + 1, this.duration);
    this.onTimeUpdate(this.currentTime);

    if (this.currentTime >= this.duration) this.pause();
  }
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}
