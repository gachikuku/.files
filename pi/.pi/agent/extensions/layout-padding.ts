import {
	AssistantMessageComponent,
	FooterComponent,
	type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";

const CONTENT_PADDING_X = 2;
const ASSISTANT_RENDER_MARK = "__layoutPaddingOriginalAssistantRender";
const FOOTER_RENDER_MARK = "__layoutPaddingOriginalFooterRender";

type Render = (this: AssistantMessageComponent, width: number) => string[];
type AssistantPrototype = {
	[ASSISTANT_RENDER_MARK]?: Render;
	render: Render;
};
type AssistantInternals = {
	outputPad: number;
};

type FooterRender = (this: FooterComponent, width: number) => string[];
type FooterPrototype = {
	[FOOTER_RENDER_MARK]?: FooterRender;
	render: FooterRender;
};

function patchAssistantPadding(): void {
	const prototype = AssistantMessageComponent.prototype as unknown as AssistantPrototype;
	prototype[ASSISTANT_RENDER_MARK] ??= prototype.render;
	const originalRender = prototype[ASSISTANT_RENDER_MARK];

	prototype.render = function (width) {
		const internals = this as unknown as AssistantInternals;
		if (internals.outputPad !== CONTENT_PADDING_X) {
			this.setOutputPad(CONTENT_PADDING_X);
		}
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
		return originalRender.call(this, innerWidth).map((line) => leftPadding + line);
	};
}

export default function (_pi: ExtensionAPI) {
	patchAssistantPadding();
	patchFooterPadding();
}
