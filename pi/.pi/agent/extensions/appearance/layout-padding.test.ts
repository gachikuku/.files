import assert from "node:assert/strict";
import test from "node:test";
import {
  AssistantMessageComponent,
  getMarkdownTheme,
  initTheme,
  ToolExecutionComponent,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import { stripTerminalSequences } from "@earendil-works/pi-tui";
import layoutPadding from "./layout-padding.ts";
import toolStatusStyle from "./tool-status-style.ts";

initTheme("dark");
layoutPadding({} as ExtensionAPI);

let bashDefinition: unknown;
toolStatusStyle({
  on: () => {},
  registerTool: (definition: { name: string }) => {
    if (definition.name === "bash") bashDefinition = definition;
  },
} as unknown as ExtensionAPI);

function plainLines(
  component: { render(width: number): string[] },
  width = 50,
) {
  return component
    .render(width)
    .map((line) => stripTerminalSequences(line).replace(/\s+$/, ""));
}

function assistantMessage(
  content: AssistantMessage["content"],
): AssistantMessage {
  return {
    role: "assistant",
    content,
    stopReason: "stop",
    usage: {},
    timestamp: Date.now(),
  } as AssistantMessage;
}

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

test("assistant content shares one column while semantic markers hang", () => {
  const lines = plainLines(
    new AssistantMessageComponent(
      assistantMessage([
        {
          type: "text",
          text: "A regular paragraph that wraps onto another line at this narrow width.\n\n- A bullet that also wraps onto another line at this narrow width.",
        },
        {
          type: "thinking",
          thinking:
            "∴ A thinking status that wraps onto another line at this narrow width.",
        },
      ]),
      false,
      getMarkdownTheme(),
      undefined,
      2,
    ),
    36,
  ).filter(Boolean);

  const regularIndex = lines.findIndex((line) => line.includes("A regular"));
  const bulletIndex = lines.findIndex((line) => line.includes("- A bullet"));
  const thinkingIndex = lines.findIndex((line) =>
    line.includes("∴ A thinking"),
  );

  assert.notEqual(regularIndex, -1);
  assert.notEqual(bulletIndex, -1);
  assert.notEqual(thinkingIndex, -1);
  assert.equal(lines[regularIndex]?.indexOf("A regular"), 2);
  assert.equal(lines[regularIndex + 1]?.search(/\S/), 2);
  assert.equal(lines[bulletIndex]?.indexOf("- A bullet"), 0);
  assert.equal(lines[bulletIndex + 1]?.search(/\S/), 2);
  assert.equal(lines[thinkingIndex]?.indexOf("∴ A thinking"), 0);
  assert.equal(lines[thinkingIndex + 1]?.search(/\S/), 2);
});

test("default and self-rendered tools use the shared content column", () => {
  const ui = { requestRender: () => {} } as never;

  const write = new ToolExecutionComponent(
    "write",
    "write-1",
    { path: "/tmp/example.ts", content: "const value = 1;" },
    {},
    undefined,
    ui,
    process.cwd(),
  );
  const writeLines = plainLines(write);
  assert.equal(
    writeLines.find((line) => line.includes("write"))?.search(/\S/),
    2,
  );
  assert.equal(
    writeLines.find((line) => line.includes("const value"))?.search(/\S/),
    2,
  );

  const edit = new ToolExecutionComponent(
    "edit",
    "edit-1",
    { path: "/tmp/example.ts", edits: [] },
    {},
    undefined,
    ui,
    process.cwd(),
  );
  assert.equal(
    plainLines(edit)
      .find((line) => line.includes("edit"))
      ?.search(/\S/),
    2,
  );
});

test("bash keeps only its prompt marker outside the content column", () => {
  assert.ok(bashDefinition);
  const bash = new ToolExecutionComponent(
    "bash",
    "bash-1",
    { command: "echo first\necho second" },
    {},
    bashDefinition as never,
    { requestRender: () => {} } as never,
    process.cwd(),
  );
  const lines = plainLines(bash).filter(Boolean);

  assert.equal(
    lines.find((line) => line.includes("$ echo first"))?.search(/\S/),
    0,
  );
  assert.equal(
    lines.find((line) => line.includes("echo second"))?.search(/\S/),
    2,
  );

  bash.updateResult({
    content: [{ type: "text", text: "ready /tmp/example" }],
    isError: false,
  });
  assert.equal(
    plainLines(bash)
      .find((line) => line.includes("ready /tmp/example"))
      ?.search(/\S/),
    2,
  );
});
