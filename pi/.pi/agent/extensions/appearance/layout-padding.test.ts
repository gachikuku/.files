import assert from "node:assert/strict";
import test from "node:test";
import {
  AssistantMessageComponent,
  getMarkdownTheme,
  initTheme,
  InteractiveMode,
  ToolExecutionComponent,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import { Container, stripTerminalSequences } from "@earendil-works/pi-tui";
import layoutPadding from "./layout-padding.ts";
import toolStatusStyle from "./tool-status-style.ts";

initTheme("dark");
layoutPadding({} as ExtensionAPI);

let bashDefinition: unknown;
toolStatusStyle({
  on: (event: string, handler: (...args: unknown[]) => void) => {
    if (event === "session_start") {
      handler(
        {},
        {
          ui: {
            theme: {
              bold: (text: string) => text,
              fg: (_color: string, text: string) => text,
            },
          },
        },
      );
    }
  },
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
  const component = new AssistantMessageComponent(
    assistantMessage([
      {
        type: "text",
        text: "A regular paragraph that wraps onto another line at this narrow width.\n\n- A hyphen list item that also wraps onto another line at this narrow width.\n\n● A semantic bullet that also wraps onto another line at this narrow width.",
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
  );

  // Editor input requests a full render per keystroke. Repeated renders must
  // not accumulate markers in Markdown's cached output.
  for (let render = 0; render < 10; render++) component.render(36);
  const lines = plainLines(component, 36).filter(Boolean);

  const regularIndex = lines.findIndex((line) => line.includes("A regular"));
  const hyphenIndex = lines.findIndex((line) => line.includes("- A hyphen"));
  const bulletIndex = lines.findIndex((line) => line.includes("● A semantic"));
  const thinkingIndex = lines.findIndex((line) =>
    line.includes("∴ A thinking"),
  );

  assert.notEqual(regularIndex, -1);
  assert.notEqual(hyphenIndex, -1);
  assert.notEqual(bulletIndex, -1);
  assert.notEqual(thinkingIndex, -1);
  assert.equal(lines[regularIndex]?.search(/\S/), 0);
  assert.equal(lines[regularIndex]?.startsWith("⏺ "), true);
  assert.equal(lines[regularIndex]?.indexOf("A regular"), 2);
  assert.equal(lines[regularIndex + 1]?.search(/\S/), 2);
  assert.equal(lines[hyphenIndex]?.indexOf("- A hyphen"), 2);
  assert.equal(lines[hyphenIndex + 1]?.search(/\S/), 4);
  assert.equal(lines[bulletIndex]?.indexOf("● A semantic"), 0);
  assert.equal(lines[bulletIndex + 1]?.search(/\S/), 2);
  assert.equal(lines[thinkingIndex]?.indexOf("∴ A thinking"), 0);
  assert.equal(lines[thinkingIndex + 1]?.search(/\S/), 2);
});

test("transcript status and warning notices use the shared content column", () => {
  const chatContainer = new Container();
  const interactive = {
    chatContainer,
    lastStatusSpacer: undefined,
    lastStatusText: undefined,
    ui: { requestRender: () => {} },
  };
  const prototype = InteractiveMode.prototype as unknown as {
    showStatus(this: typeof interactive, message: string): void;
    showWarning(this: typeof interactive, message: string): void;
  };

  prototype.showStatus.call(interactive, "Reloaded extensions");
  prototype.showStatus.call(interactive, "Reloaded keybindings and extensions");
  prototype.showWarning.call(
    interactive,
    "Wait for the current response to finish before reloading.",
  );

  const lines = plainLines(chatContainer);
  const status = lines.find((line) => line.includes("Reloaded keybindings"));
  const warning = lines.find((line) => line.includes("Warning: Wait"));
  assert.equal(status?.search(/\S/), 0);
  assert.equal(status?.indexOf("Reloaded"), 2);
  assert.equal(warning?.search(/\S/), 0);
  assert.equal(warning?.indexOf("Warning"), 2);
});

test("cache-miss warnings use a hanging dot in the warning color", () => {
  const chatContainer = new Container();
  const interactive = { chatContainer };
  const addCacheMissNotice = (
    InteractiveMode.prototype as unknown as {
      addCacheMissNotice(
        this: typeof interactive,
        miss: {
          idleMs: number;
          missedCost: number;
          missedTokens: number;
          modelChanged: boolean;
        },
      ): void;
    }
  ).addCacheMissNotice;

  addCacheMissNotice.call(interactive, {
    idleMs: 241 * 60_000,
    missedCost: 0.14,
    missedTokens: 30_000,
    modelChanged: false,
  });

  const renderedLine = chatContainer
    .render(80)
    .find((line) => line.includes("Cache miss"));
  const plainLine = renderedLine && stripTerminalSequences(renderedLine);
  assert.equal(plainLine?.search(/\S/), 0);
  assert.equal(plainLine?.indexOf("Cache miss"), 2);
  assert.match(renderedLine ?? "", /\x1b\[[0-9;]*m⏺ Cache miss/);
});

test("assistant errors use a hanging status dot without a redundant label", () => {
  const errorMessage = {
    ...assistantMessage([]),
    stopReason: "error",
    errorMessage: "API Error: 400 unsupported model",
  } as AssistantMessage;
  const lines = plainLines(
    new AssistantMessageComponent(
      errorMessage,
      false,
      getMarkdownTheme(),
      undefined,
      2,
    ),
    32,
  );
  const errorLine = lines.find((line) => line.includes("API Error"));

  assert.equal(errorLine?.search(/\S/), 0);
  assert.equal(errorLine?.indexOf("API Error"), 2);
  assert.equal(errorLine?.includes("Error: API Error"), false);
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
  const writeCall = writeLines.find((line) => line.includes("write"));
  assert.equal(writeCall?.search(/\S/), 0);
  assert.equal(writeCall?.indexOf("write"), 2);
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
  const editCall = plainLines(edit).find((line) => line.includes("edit"));
  assert.equal(editCall?.search(/\S/), 0);
  assert.equal(editCall?.indexOf("edit"), 2);
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

  const bashCall = lines.find((line) => line.includes("$ echo first"));
  assert.equal(bashCall?.search(/\S/), 0);
  assert.equal(bashCall?.indexOf("$ echo first"), 2);
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
