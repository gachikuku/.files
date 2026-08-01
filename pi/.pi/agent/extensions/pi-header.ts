import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

type Rgb = [number, number, number];

const RESET = "\x1b[0m";

// A Flexoki-green version of Davis's blue gradient. The middle shade is the
// exact #547565 used by this setup for inline code.
const PALETTE: Rgb[] = [
	[52, 74, 64],
	[70, 97, 84],
	[84, 117, 101],
	[105, 132, 121],
	[127, 151, 139],
	[105, 132, 121],
];

const PI = [
	" ▄████████████████ ",
	"██   ███    ███    ",
	"▀    ███    ███    ",
	"     ███    ███    ",
	"    ▄██     ███    ",
	"    ███     ███  ▄ ",
	"   ███      ▀██▄██ ",
	"   ███       ████▀ ",
	"   ▀▀▀        ▀▀   ",
];

function mix(start: number, end: number, amount: number): number {
	return Math.round(start + (end - start) * amount);
}

function sampleGradient(position: number): Rgb {
	const wrapped = ((position % 1) + 1) % 1;
	const scaled = wrapped * PALETTE.length;
	const index = Math.floor(scaled);
	const nextIndex = (index + 1) % PALETTE.length;
	const amount = scaled - index;
	const start = PALETTE[index]!;
	const end = PALETTE[nextIndex]!;

	return [
		mix(start[0], end[0], amount),
		mix(start[1], end[1], amount),
		mix(start[2], end[2], amount),
	];
}

function foreground([red, green, blue]: Rgb, text: string): string {
	return `\x1b[38;2;${red};${green};${blue}m${text}${RESET}`;
}

function gradient(text: string, phase: number): string {
	const characters = [...text];
	const span = Math.max(characters.length - 1, 1);

	return characters
		.map((character, index) =>
			character === " "
				? character
				: foreground(sampleGradient(index / span + phase), character),
		)
		.join("");
}

function center(text: string, width: number): string {
	const padding = Math.max(0, Math.floor((width - visibleWidth(text)) / 2));
	return truncateToWidth(`${" ".repeat(padding)}${text}`, width, "");
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		if (ctx.mode !== "tui") return;

		ctx.ui.setHeader(() => ({
			render(width: number): string[] {
				return PI.map((line, row) =>
					center(gradient(line, row * 0.045), width),
				);
			},
			invalidate() {},
		}));
	});
}
