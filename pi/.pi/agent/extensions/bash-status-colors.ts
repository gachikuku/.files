import { createBashTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";

const SUCCESS_COLOR = "\x1b[38;2;104;134;99m";
const RESET_FG = "\x1b[39m";

/**
 * Render bash commands without a background:
 * - yellow while pending
 * - green after success
 * - red after failure
 */
export default function bashStatusColors(pi: ExtensionAPI) {
	const bash = createBashTool(process.cwd());

	pi.registerTool({
		...bash,
		renderShell: "self",
		renderCall(args, theme, context) {
			const command = args.command || "...";
			const commandText = theme.bold(`$ ${command}`);
			let content = context.isPartial
				? theme.fg("warning", commandText)
				: context.isError
					? theme.fg("error", commandText)
					: `${SUCCESS_COLOR}${commandText}${RESET_FG}`;

			if (args.timeout) {
				content += theme.fg("dim", ` (timeout ${args.timeout}s)`);
			}

			const text = (context.lastComponent as Text | undefined) ?? new Text("", 0, 0);
			text.setText(content);
			return text;
		},
	});
}
