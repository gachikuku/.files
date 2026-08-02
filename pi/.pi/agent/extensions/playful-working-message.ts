import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type RGB = readonly [red: number, green: number, blue: number];

const BASE: RGB = [204, 139, 137];
const BRIGHT: RGB = [255, 218, 213];
const LIGHT: RGB = [236, 184, 180];
const RESET_FG = "\x1b[39m";
const CLAUDE_SPINNER = ["✻", "✽", "✶", "✳", "✢", "·", "✢", "✳", "✶", "✽"];

function colorize(text: string, [red, green, blue]: RGB): string {
	return `\x1b[38;2;${red};${green};${blue}m${text}${RESET_FG}`;
}

function makeClaudeStyleFrames(message: string): string[] {
	const characters = [...message];
	const frameCount = characters.length + 6;

	return Array.from({ length: frameCount }, (_, frameIndex) => {
		const highlightPosition = frameIndex - 3;
		const animatedMessage = characters
			.map((character, characterIndex) => {
				const distance = Math.abs(characterIndex - highlightPosition);
				const color = distance === 0 ? BRIGHT : distance <= 2 ? LIGHT : BASE;
				return colorize(character, color);
			})
			.join("");
		const spinner = CLAUDE_SPINNER[frameIndex % CLAUDE_SPINNER.length]!;

		return `${colorize(spinner, BASE)} ${animatedMessage}`;
	});
}

const WORKING_MESSAGES = [
	"Lollygagging...",
	"Gagging...",
	"Pondering...",
	"Fipfapping...",
	"Fapping...",
	"Percolating...",
	"Tinkering...",
	"Scheming...",
	"Cogitating...",
	"Moseying...",
	"Salivating...",
	"Saliva build up...",
	"Stretching...",
	"Fingering...",
	"Mansplaying...",
	"Ruminating...",
	"Lubricating...",
	"Noodling...",
	"Swallowing...",
	"Conjuring...",
	"Scribbling...",
	"Untangling...",
	"Investigating...",
	"Crunching...",
	"Herding bits...",
	"Consulting the void...",
	"Polishing pixels...",
	"Chasing semicolons...",
	"Summoning electrons...",
	"Connecting dots...",
] as const;

export default function (pi: ExtensionAPI) {
	let previousIndex = -1;

	pi.on("before_agent_start", (_event, ctx) => {
		if (ctx.mode !== "tui") return;

		let index = Math.floor(Math.random() * WORKING_MESSAGES.length);
		if (WORKING_MESSAGES.length > 1 && index === previousIndex) {
			index = (index + 1) % WORKING_MESSAGES.length;
		}

		previousIndex = index;
		ctx.ui.setWorkingMessage("");
		ctx.ui.setWorkingIndicator({
			frames: makeClaudeStyleFrames(WORKING_MESSAGES[index]),
			intervalMs: 140,
		});
	});
}
