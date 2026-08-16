import {
  AssistantMessageComponent,
  FooterComponent,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import type { MarkdownTheme } from "@earendil-works/pi-tui";

const CONTENT_PADDING_X = 2;
const ASSISTANT_RENDER_MARK = "__layoutPaddingOriginalAssistantRender";
const FOOTER_RENDER_MARK = "__layoutPaddingOriginalFooterRender";
const PLAIN_LINK_THEME_MARK = Symbol.for("pi.appearance.plainLinkTheme");
const UNDERLINE_SGR = /\x1b\[(?:4|24)m/g;

type Render = (this: AssistantMessageComponent, width: number) => string[];
type AssistantPrototype = {
  [ASSISTANT_RENDER_MARK]?: Render;
  render: Render;
};
type AssistantInternals = {
  contentContainer?: { children: unknown[] };
  outputPad: number;
};
type MarkdownInternals = {
  invalidate(): void;
  paddingX: number;
  text: string;
  theme?: PlainLinkTheme;
};
type PlainLinkTheme = MarkdownTheme & {
  [PLAIN_LINK_THEME_MARK]?: boolean;
};

type FooterRender = (this: FooterComponent, width: number) => string[];
type FooterPrototype = {
  [FOOTER_RENDER_MARK]?: FooterRender;
  render: FooterRender;
};

function styleAssistantMarkdown(component: AssistantMessageComponent): void {
  const { contentContainer } = component as unknown as AssistantInternals;
  for (const child of contentContainer?.children ?? []) {
    const markdown = child as unknown as MarkdownInternals;
    if (
      typeof markdown.text !== "string" ||
      typeof markdown.paddingX !== "number" ||
      typeof markdown.invalidate !== "function"
    ) {
      continue;
    }

    const markdownTheme = markdown.theme;
    if (markdownTheme && !markdownTheme[PLAIN_LINK_THEME_MARK]) {
      const originalLink = markdownTheme.link;
      markdownTheme.link = (text) =>
        originalLink(text.replace(UNDERLINE_SGR, ""));
      markdownTheme[PLAIN_LINK_THEME_MARK] = true;
      markdown.invalidate();
    }

    if (!markdown.text.trimStart().startsWith("∴")) continue;
    if (markdown.paddingX === 0) continue;

    markdown.paddingX = 0;
    markdown.invalidate();
  }
}

function patchAssistantPadding(): void {
  const prototype =
    AssistantMessageComponent.prototype as unknown as AssistantPrototype;
  prototype[ASSISTANT_RENDER_MARK] ??= prototype.render;
  const originalRender = prototype[ASSISTANT_RENDER_MARK];

  prototype.render = function (width) {
    const internals = this as unknown as AssistantInternals;
    if (internals.outputPad !== CONTENT_PADDING_X) {
      this.setOutputPad(CONTENT_PADDING_X);
    }
    styleAssistantMarkdown(this);
    return originalRender.call(this, width);
  };
}

function patchFooterPadding(): void {
  const prototype = FooterComponent.prototype as unknown as FooterPrototype;
  prototype[FOOTER_RENDER_MARK] ??= prototype.render;
  const originalRender = prototype[FOOTER_RENDER_MARK];

  prototype.render = function (width) {
    const innerWidth = Math.max(1, width - CONTENT_PADDING_X * 2);
    const leftPadding = " ".repeat(CONTENT_PADDING_X);
    return originalRender
      .call(this, innerWidth)
      .map((line) => leftPadding + line);
  };
}

export default function (_pi: ExtensionAPI) {
  patchAssistantPadding();
  patchFooterPadding();
}
