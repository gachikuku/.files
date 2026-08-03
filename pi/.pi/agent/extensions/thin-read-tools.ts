import { ToolExecutionComponent, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Box } from "@earendil-works/pi-tui";

const ORIGINAL_UPDATE_MARK = "__thinFileToolsOriginalUpdateDisplay";

type ToolExecutionInternals = {
	toolName: string;
	contentBox: Box;
	selfRenderContainer: { children: unknown[] };
};

type UpdateDisplay = (this: ToolExecutionInternals) => void;

type ToolExecutionPrototype = {
	[ORIGINAL_UPDATE_MARK]?: UpdateDisplay;
	updateDisplay: UpdateDisplay;
};

type MutableBox = Box & { paddingY: number };

export default function (_pi: ExtensionAPI) {
	const prototype = ToolExecutionComponent.prototype as unknown as ToolExecutionPrototype;
	prototype[ORIGINAL_UPDATE_MARK] ??= prototype.updateDisplay;
	const originalUpdateDisplay = prototype[ORIGINAL_UPDATE_MARK];

	prototype.updateDisplay = function () {
		originalUpdateDisplay.call(this);

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
}
