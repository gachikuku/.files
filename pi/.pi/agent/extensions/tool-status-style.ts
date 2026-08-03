import {
	createBashTool,
	ToolExecutionComponent,
	type ExtensionAPI,
	type Theme,
	type ThemeColor,
} from "@earendil-works/pi-coding-agent";
import { Box, Text } from "@earendil-works/pi-tui";

const ORIGINAL_UPDATE_MARK = "__thinFileToolsOriginalUpdateDisplay";
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

function findFirstText(component: unknown): Text | undefined {
	if (component instanceof Text) return component;
	if (!component || typeof component !== "object" || !("children" in component)) return undefined;

	for (const child of (component as ChildContainer).children) {
		const text = findFirstText(child);
		if (text) return text;
	}
	return undefined;
}

function recolorKeyword(component: unknown, theme: Theme, color: ThemeColor): void {
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

export default function (pi: ExtensionAPI) {
	let activeTheme: Theme | undefined;

	pi.on("session_start", (_event, ctx) => {
		activeTheme = ctx.ui.theme;
	});

	const prototype = ToolExecutionComponent.prototype as unknown as ToolExecutionPrototype;
	prototype[ORIGINAL_UPDATE_MARK] ??= prototype.updateDisplay;
	const originalUpdateDisplay = prototype[ORIGINAL_UPDATE_MARK];

	prototype.updateDisplay = function () {
		originalUpdateDisplay.call(this);

		if (this.toolName !== "read" && this.toolName !== "write" && this.toolName !== "edit") return;

		if (activeTheme) {
			const statusColor: ThemeColor = this.isPartial ? "warning" : this.result?.isError ? "error" : "success";
			recolorKeyword(this.callRendererComponent, activeTheme, statusColor);
		}

		if ((this.toolName === "read" || this.toolName === "write") && this.contentBox instanceof Box) {
			(this.contentBox as MutableBox).paddingY = 0;
			this.contentBox.invalidate();
		}

		if (this.toolName === "edit") {
			const editBox = this.selfRenderContainer.children.find((child) => child instanceof Box);
			if (editBox instanceof Box) {
				(editBox as MutableBox).paddingY = 0;
				editBox.invalidate();
			}
		}
	};

	const bash = createBashTool(process.cwd());
	pi.registerTool({
		...bash,
		renderShell: "self",
		renderCall(args, theme, context) {
			const color: ThemeColor = context.isPartial ? "warning" : context.isError ? "error" : "success";
			const command = args.command || "...";
			let content = theme.fg(color, theme.bold(`$ ${command}`));

			if (args.timeout) {
				content += theme.fg("dim", ` (timeout ${args.timeout}s)`);
			}

			const text = (context.lastComponent as Text | undefined) ?? new Text("", 0, 0);
			text.setText(content);
			return text;
		},
	});
}
