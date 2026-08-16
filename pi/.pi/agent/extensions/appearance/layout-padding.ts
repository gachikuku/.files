import {
  AssistantMessageComponent,
  FooterComponent,
  ToolExecutionComponent,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import {
  Box,
  type Component,
  Container,
  Markdown,
  type MarkdownTheme,
  sliceByColumn,
  Spacer,
  stripTerminalSequences,
  Text,
} from "@earendil-works/pi-tui";

export const CONTENT_PADDING_X = 2;

const ASSISTANT_RENDER_MARK = "__layoutPaddingOriginalAssistantRender";
const FOOTER_RENDER_MARK = "__layoutPaddingOriginalFooterRender";
const MARKER_RENDER_MARK = Symbol.for("pi.appearance.markerOutdentRender");
const PLAIN_LINK_THEME_MARK = Symbol.for("pi.appearance.plainLinkTheme");
const UNDERLINE_SGR = /\x1b\[(?:4|24)m/g;
const HANGING_MARKER = /^(?:∴|✻|✽|✶|✳|✢|※|⏺|●|•|·|\$|[-+*]|\d+[.)])(?:\s|$)/;
const LIST_MARKER = /^(?:⏺|●|•|[-+*]|\d+[.)])(?:\s|$)/;

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
  render(width: number): string[];
  text: string;
  theme?: PlainLinkTheme;
  [MARKER_RENDER_MARK]?: (width: number) => string[];
};
type PlainLinkTheme = MarkdownTheme & {
  [PLAIN_LINK_THEME_MARK]?: boolean;
};

type FooterRender = (this: FooterComponent, width: number) => string[];
type FooterPrototype = {
  [FOOTER_RENDER_MARK]?: FooterRender;
  render: FooterRender;
};

type MutablePadding = {
  invalidate(): void;
  paddingX: number;
};
type MarkerRenderable = Component & {
  [MARKER_RENDER_MARK]?: (width: number) => string[];
};
type ToolExecutionInternals = {
  callRendererComponent?: Component;
  contentBox: Box;
  contentText: Text;
  resultRendererComponent?: Component;
  selfRenderContainer: Container;
};

function visibleText(line: string): string {
  return stripTerminalSequences(line).replace(/\s+$/, "");
}

function leadingSpaces(text: string): number {
  return text.match(/^ */)?.[0].length ?? 0;
}

function outdent(line: string, columns: number, width: number): string {
  return sliceByColumn(line, columns, Math.max(1, width - columns), true);
}

/** Keep ordinary content on column 2 while allowing semantic glyphs to hang. */
function patchMarkerOutdent(component: MarkerRenderable): void {
  if (component[MARKER_RENDER_MARK]) return;

  const originalRender = component.render.bind(component);
  component[MARKER_RENDER_MARK] = originalRender;
  component.render = (width: number) => {
    let inList = false;
    return originalRender(width).map((line) => {
      const plain = visibleText(line);
      if (!plain.trim()) return line;

      const indent = leadingSpaces(plain);
      const content = plain.slice(indent);
      if (indent >= CONTENT_PADDING_X && HANGING_MARKER.test(content)) {
        inList = LIST_MARKER.test(content);
        return outdent(line, CONTENT_PADDING_X, width);
      }

      // Markdown list continuations already have their own marker-width indent.
      // Remove only the shared outer padding so they align with the item text.
      if (inList && indent > CONTENT_PADDING_X) {
        return outdent(line, CONTENT_PADDING_X, width);
      }

      if (indent <= CONTENT_PADDING_X) inList = false;
      return line;
    });
  };
}

function hasPaddingX(
  component: Component,
): component is Component & MutablePadding {
  return (
    "paddingX" in component &&
    typeof (component as unknown as MutablePadding).paddingX === "number"
  );
}

function childComponents(component: Component): Component[] | undefined {
  if (!("children" in component)) return undefined;
  const children = (component as { children?: unknown }).children;
  return Array.isArray(children) ? (children as Component[]) : undefined;
}

function setPaddingX(component: Component & MutablePadding): void {
  if (component.paddingX === CONTENT_PADDING_X) return;
  component.paddingX = CONTENT_PADDING_X;
  component.invalidate();
}

function padSelfRenderedComponent(
  component: Component,
  allowHangingMarker: boolean,
): Component {
  // Tool renderers may come from a second resolved copy of pi-tui, so use the
  // component shape rather than relying only on cross-package instanceof.
  if (hasPaddingX(component)) {
    setPaddingX(component);
    if (allowHangingMarker) patchMarkerOutdent(component);
    return component;
  }

  if (component instanceof Spacer || component.constructor?.name === "Spacer")
    return component;

  const children = childComponents(component);
  if (children) {
    (component as { children: Component[] }).children = children.map((child) =>
      padSelfRenderedComponent(child, allowHangingMarker),
    );
    component.invalidate();
    return component;
  }

  // Width-aware custom renderers have no padding field. Give them the same
  // symmetric content inset without changing their implementation.
  const wrapper = new Box(CONTENT_PADDING_X, 0);
  wrapper.addChild(component);
  if (allowHangingMarker) patchMarkerOutdent(wrapper);
  return wrapper;
}

/** Normalize built-in, custom, default-shell, and self-shell tool rows. */
export function styleToolContentPadding(
  component: ToolExecutionComponent,
): void {
  const internals = component as unknown as ToolExecutionInternals;
  setPaddingX(internals.contentBox);
  setPaddingX(internals.contentText);

  if (internals.selfRenderContainer.children.length === 0) return;

  internals.selfRenderContainer.children =
    internals.selfRenderContainer.children.map((child) =>
      padSelfRenderedComponent(
        child,
        child === internals.callRendererComponent,
      ),
    );
  internals.selfRenderContainer.invalidate();
}

function styleAssistantMarkdown(component: AssistantMessageComponent): void {
  const { contentContainer } = component as unknown as AssistantInternals;
  for (const child of contentContainer?.children ?? []) {
    const markdown = child as unknown as MarkdownInternals;
    if (
      typeof markdown.text !== "string" ||
      typeof markdown.paddingX !== "number" ||
      typeof markdown.render !== "function" ||
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

    setPaddingX(child as Markdown);
    patchMarkerOutdent(child as MarkerRenderable);
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
