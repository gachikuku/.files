import { createBashTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";

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
			const color = context.isPartial
				? "warning"
				: context.isError
					? "error"
					: "success";
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
