import {
  AssistantMessageComponent,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import type { MarkdownTheme } from "@earendil-works/pi-tui";

const ORIGINAL_RENDER_MARK = "__plainLinksOriginalRender";
const PLAIN_LINK_THEME_MARK = Symbol.for("pi.appearance.plainLinkTheme");
const UNDERLINE_SGR = /\x1b\[(?:4|24)m/g;

type Render = (this: AssistantMessageComponent, width: number) => string[];
type AssistantPrototype = {
  [ORIGINAL_RENDER_MARK]?: Render;
  render: Render;
};
type AssistantInternals = {
  contentContainer?: { children: unknown[] };
};
type PlainLinkTheme = MarkdownTheme & {
  [PLAIN_LINK_THEME_MARK]?: boolean;
};
type MarkdownInternals = {
  invalidate?: () => void;
  theme?: PlainLinkTheme;
};

function removeLinkUnderlines(component: AssistantMessageComponent): void {
  const { contentContainer } = component as unknown as AssistantInternals;
  for (const child of contentContainer?.children ?? []) {
    const markdown = child as MarkdownInternals;
    const markdownTheme = markdown.theme;
    if (!markdownTheme || markdownTheme[PLAIN_LINK_THEME_MARK]) continue;

    const originalLink = markdownTheme.link;
    markdownTheme.link = (text) =>
      originalLink(text.replace(UNDERLINE_SGR, ""));
    markdownTheme[PLAIN_LINK_THEME_MARK] = true;
    markdown.invalidate?.();
  }
}

export default function (_pi: ExtensionAPI) {
  const prototype =
    AssistantMessageComponent.prototype as unknown as AssistantPrototype;
  prototype[ORIGINAL_RENDER_MARK] ??= prototype.render;
  const originalRender = prototype[ORIGINAL_RENDER_MARK];

  prototype.render = function (width) {
    removeLinkUnderlines(this);
    return originalRender.call(this, width);
  };
}
