import assert from "node:assert/strict";
import test from "node:test";
import { YouTubePlayer } from "../src/player.ts";

test("late YouTube ready/state callbacks cannot reclaim the clock after source replacement", async () => {
  let polls = 0;
  const instances: Array<{ events: { onReady(): void; onStateChange(event: { data: number }): void } }> = [];
  class FakePlayer {
    constructor(_id: string, options: typeof instances[number]) { instances.push(options); }
    pauseVideo() {}
    destroy() {}
  }
  const yt = { Player: FakePlayer, PlayerState: { PLAYING: 1 } };
  const original = ["window", "document", "YT"].map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)] as const);
  Object.defineProperty(globalThis, "window", { configurable: true, value: {
    YT: yt, setInterval: () => { polls++; return 100; },
  }});
  Object.defineProperty(globalThis, "YT", { configurable: true, value: yt });
  Object.defineProperty(globalThis, "document", { configurable: true, value: {
    getElementById: () => ({ innerHTML: "", appendChild() {} }),
    createElement: () => ({ id: "" }),
  }});
  try {
    const player = new YouTubePlayer("container", () => {}, () => {});
    const firstLoad = player.loadVideo("aaaaaaaaaaa");
    await Promise.resolve();
    player.stop();
    instances[0].events.onReady();
    instances[0].events.onStateChange({ data: 1 });
    await firstLoad;
    assert.equal(polls, 0);
    const secondLoad = player.loadVideo("bbbbbbbbbbb");
    await Promise.resolve();
    instances[1].events.onReady();
    await secondLoad;
    assert.equal(polls, 1);
    instances[0].events.onReady();
    instances[0].events.onStateChange({ data: 1 });
    assert.equal(polls, 1);
    player.stop();
  } finally {
    for (const [key, descriptor] of original) {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor);
      else Reflect.deleteProperty(globalThis, key);
    }
  }
});
