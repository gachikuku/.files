import assert from "node:assert/strict";
import test from "node:test";
import {
  AssistantMessageComponent,
  getMarkdownTheme,
  initTheme,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import layoutPadding from "./layout-padding.ts";

initTheme("dark");
layoutPadding({} as ExtensionAPI);

test("assistant links lose their underline while heading styling remains", () => {
  const markdownTheme = getMarkdownTheme();
  markdownTheme.underline = (text) => `\x1b[4m${text}\x1b[24m`;
  const message = {
    role: "assistant",
    content: [
      {
        type: "text",
        text: "[OpenAI](https://openai.com)\n\n# Heading",
      },
    ],
    stopReason: "stop",
    usage: {},
    timestamp: Date.now(),
  } as AssistantMessage;

  const lines = new AssistantMessageComponent(
    message,
    false,
    markdownTheme,
    undefined,
    2,
  ).render(80);
  const linkLine = lines.find((line) => line.includes("OpenAI"));
  const headingLine = lines.find((line) => line.includes("Heading"));

  assert.ok(linkLine);
  assert.doesNotMatch(linkLine, /\x1b\[(?:4|24)m/);
  assert.ok(headingLine);
  assert.match(headingLine, /\x1b\[4mHeading\x1b\[24m/);
});
