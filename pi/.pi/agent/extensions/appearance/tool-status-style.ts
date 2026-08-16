import {
  createBashTool,
  ToolExecutionComponent,
  type ExtensionAPI,
  type Theme,
  type ThemeColor,
} from "@earendil-works/pi-coding-agent";
import { Box, Text } from "@earendil-works/pi-tui";

const ORIGINAL_UPDATE_MARK = "__thinFileToolsOriginalUpdateDisplay";
const DIFF_ADDED_BG = "\x1b[48;2;223;254;218m";
const DIFF_ADDED_HIGHLIGHT_BG = "\x1b[48;2;192;253;182m";
const DIFF_REMOVED_BG = "\x1b[48;2;249;216;216m";
const DIFF_REMOVED_HIGHLIGHT_BG = "\x1b[48;2;249;184;184m";
const RESET_BG = "\x1b[49m";
const INVERSE_START = "\u0001";
const INVERSE_END = "\u0002";
const SGR = /\x1b\[[0-9;]*m/g;

type ToolExecutionInternals = {
  toolName: string;
  contentBox: Box;
  selfRenderContainer: { children: unknown[] };
  callRendererComponent?: unknown;
  isPartial: boolean;
  result?: { isError: boolean };
};

type UpdateDisplay = (this: ToolExecutionInternals) => void;

type ToolExecutionPrototype = {
  [ORIGINAL_UPDATE_MARK]?: UpdateDisplay;
  updateDisplay: UpdateDisplay;
};

type MutableBox = Box & { paddingY: number };
type MutableText = Text & { text: string };
type ChildContainer = { children: unknown[] };

function findAllText(component: unknown): Text[] {
  if (component instanceof Text) return [component];
  if (!component || typeof component !== "object" || !("children" in component))
    return [];
  return (component as ChildContainer).children.flatMap(findAllText);
}

function findFirstText(component: unknown): Text | undefined {
  return findAllText(component)[0];
}

function recolorKeyword(
  component: unknown,
  theme: Theme,
  color: ThemeColor,
): void {
  const textComponent = findFirstText(component);
  if (!textComponent) return;

  const mutableText = textComponent as MutableText;
  const [firstLine, ...remainingLines] = mutableText.text.split("\n");
  const plainFirstLine = firstLine.replace(SGR, "");
  const match = plainFirstLine.match(/^(\S+)(.*)$/);
  if (!match) return;

  const [, keyword, rest] = match;
  const recoloredFirstLine = `${theme.fg(color, theme.bold(keyword))}${rest}`;
  textComponent.setText([recoloredFirstLine, ...remainingLines].join("\n"));
}

function highlightChangedWords(
  content: string,
  baseBackground: string,
  highlightBackground: string,
): string {
  return content
    .replaceAll(INVERSE_START, highlightBackground)
    .replaceAll(INVERSE_END, baseBackground);
}

function styleDiff(component: unknown, theme: Theme): void {
  for (const textComponent of findAllText(component).slice(1)) {
    const mutableText = textComponent as MutableText;
    const lines = mutableText.text.split("\n");
    const parsed = lines.map((line) => {
      const plain = line
        .replaceAll("\x1b[7m", INVERSE_START)
        .replaceAll("\x1b[27m", INVERSE_END)
        .replace(SGR, "");
      const match = plain.match(/^([+\- ])(\s*\d*)\s(.*)$/);
      return match
        ? {
            prefix: match[1]!,
            lineNumber: match[2]!.trim(),
            content: match[3]!,
          }
        : undefined;
    });
    if (!parsed.some(Boolean)) continue;

    const lineNumberWidth = Math.max(
      1,
      ...parsed.map((line) => line?.lineNumber.length ?? 0),
    );
    const styledLines = lines.map((line, index) => {
      const diffLine = parsed[index];
      if (!diffLine) return `${RESET_BG}${line.replace(SGR, "")}`;

      const lineNumber = diffLine.lineNumber.padStart(lineNumberWidth);
      if (diffLine.prefix === "+") {
        const gutter = theme.fg("toolDiffAdded", `${lineNumber} +`);
        const content = highlightChangedWords(
          diffLine.content,
          DIFF_ADDED_BG,
          DIFF_ADDED_HIGHLIGHT_BG,
        );
        return `${DIFF_ADDED_BG}${gutter}${content}`;
      }
      if (diffLine.prefix === "-") {
        const gutter = theme.fg("toolDiffRemoved", `${lineNumber} -`);
        const content = highlightChangedWords(
          diffLine.content,
          DIFF_REMOVED_BG,
          DIFF_REMOVED_HIGHLIGHT_BG,
        );
        return `${DIFF_REMOVED_BG}${gutter}${content}`;
      }

      const gutter = theme.fg("dim", lineNumber);
      return `${RESET_BG}${gutter}  ${diffLine.content}`;
    });
    textComponent.setText(styledLines.join("\n"));
  }
}

export default function (pi: ExtensionAPI) {
  let activeTheme: Theme | undefined;

  pi.on("session_start", (_event, ctx) => {
    activeTheme = ctx.ui.theme;
  });

  const prototype =
    ToolExecutionComponent.prototype as unknown as ToolExecutionPrototype;
  prototype[ORIGINAL_UPDATE_MARK] ??= prototype.updateDisplay;
  const originalUpdateDisplay = prototype[ORIGINAL_UPDATE_MARK];

  prototype.updateDisplay = function () {
    originalUpdateDisplay.call(this);

    if (
      this.toolName !== "read" &&
      this.toolName !== "write" &&
      this.toolName !== "edit"
    )
      return;

    if (activeTheme) {
      const statusColor: ThemeColor = this.isPartial
        ? "warning"
        : this.result?.isError
          ? "error"
          : "success";
      recolorKeyword(this.callRendererComponent, activeTheme, statusColor);
    }

    if (
      (this.toolName === "read" || this.toolName === "write") &&
      this.contentBox instanceof Box
    ) {
      (this.contentBox as MutableBox).paddingY = 0;
      this.contentBox.invalidate();
    }

    if (this.toolName === "edit") {
      const editBox = this.selfRenderContainer.children.find(
        (child) => child instanceof Box,
      );
      if (editBox instanceof Box) {
        (editBox as MutableBox).paddingY = 0;
        if (activeTheme) styleDiff(editBox, activeTheme);
        editBox.invalidate();
      }
    }
  };

  const bash = createBashTool(process.cwd());
  pi.registerTool({
    ...bash,
    renderShell: "self",
    renderCall(args, theme, context) {
      const color: ThemeColor = context.isPartial
        ? "warning"
        : context.isError
          ? "error"
          : "success";
      const command = args.command || "...";
      let content = theme.fg(color, theme.bold(`$ ${command}`));

      if (args.timeout) {
        content += theme.fg("dim", ` (timeout ${args.timeout}s)`);
      }

      const text =
        (context.lastComponent as Text | undefined) ?? new Text("", 0, 0);
      text.setText(content);
      return text;
    },
  });
}
