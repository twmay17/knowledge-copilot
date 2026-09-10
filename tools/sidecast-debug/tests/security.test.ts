import assert from "node:assert/strict";
import test from "node:test";
import { exportSettingsJSON, loadSettings, saveSettings } from "../src/settings.ts";
import { renderSidecastBubbles, renderTranscriptViewer } from "../src/ui.ts";

test("keys remain in memory, never preferences or exported presets; old keys are purged", () => {
  const values = new Map<string, string>();
  Object.defineProperty(globalThis, "localStorage", { configurable: true, value: {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
  }});
  try {
    const settings = loadSettings();
    settings.apiKey = "SYNTHETIC-SECRET-ONLY";
    saveSettings(settings);
    assert.equal(settings.apiKey, "SYNTHETIC-SECRET-ONLY");
    assert.ok(![...values.values()].join("").includes(settings.apiKey));
    assert.ok(!exportSettingsJSON(settings).includes(settings.apiKey));
    assert.ok(!("apiKey" in JSON.parse(exportSettingsJSON(settings))));
    values.set("sidecast-debug-settings", JSON.stringify(settings));
    assert.equal(loadSettings().apiKey, "");
    assert.ok(![...values.values()].join("").includes(settings.apiKey));
  } finally {
    Reflect.deleteProperty(globalThis, "localStorage");
  }
});

// A deliberately strict DOM double: any attempt to parse nonempty HTML fails.
// This tests the actual render functions without a browser, network or secrets.
class Element {
  className = "";
  textContent = "";
  style: Record<string, string> = {};
  children: Element[] = [];
  set innerHTML(value: string) {
    assert.equal(value, "", "Untrusted output must not use HTML parsing");
    this.children = [];
  }
  append(...children: Element[]) { this.children.push(...children); }
  appendChild(child: Element) { this.children.push(child); return child; }
  addEventListener() {}
  get allText(): string { return this.textContent + this.children.map(c => c.allText).join(""); }
}

test("transcript and answer/persona markup stays literal text; color cannot inject attributes", () => {
  Object.defineProperty(globalThis, "document", { configurable: true, value: {
    createElement: () => new Element(),
    createTextNode: (text: string) => Object.assign(new Element(), { textContent: text }),
  }});
  try {
    const hostile = '<img src=x onerror="throw 1">';
    const transcript = new Element();
    renderTranscriptViewer(transcript as unknown as HTMLElement, [{ start: 120, duration: 2, text: hostile }], -1, () => {});
    assert.equal(transcript.allText, "2:00" + hostile);
    const output = new Element();
    renderSidecastBubbles(output as unknown as HTMLElement,
      [{ personaName: hostile, text: hostile, confidence: 1, priority: 1, value: 1, personaId: "one" }],
      [{ id: "one", avatarTint: 'red" onmouseover="bad', avatarEmoji: hostile } as never]);
    assert.ok(output.allText.includes(hostile));
    assert.equal(output.children[0].children[0].children[0].style.color, "#666666");
  } finally {
    Reflect.deleteProperty(globalThis, "document");
  }
});
