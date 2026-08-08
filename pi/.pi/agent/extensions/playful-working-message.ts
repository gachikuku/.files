import { AssistantMessageComponent, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import {
	type DefaultTextStyle,
	Markdown,
	type MarkdownTheme,
	Text,
} from "@earendil-works/pi-tui";

type RGB = readonly [red: number, green: number, blue: number];

const BASE: RGB = [204, 139, 137];
const SUMMARY: RGB = [98, 98, 98];
const BRIGHT: RGB = [255, 218, 213];
const LIGHT: RGB = [236, 184, 180];
const RESET_FG = "\x1b[39m";
const CLAUDE_SPINNER = ["✻", "✽", "✶", "✳", "✢", "·", "✢", "✳", "✶", "✽"];
const ANIMATION_INTERVAL_MS = 140;

const DURATION_ENTRY_TYPE = "playful-working-duration";
const ORIGINAL_ASSISTANT_UPDATE_MARK = "__thinkingPrefixOriginalUpdateContent";

function colorize(text: string, [red, green, blue]: RGB): string {
	return `\x1b[38;2;${red};${green};${blue}m${text}${RESET_FG}`;
}

type UpdateAssistantContent = (this: AssistantMessageComponent, message: AssistantMessage) => void;
type AssistantMessagePrototype = {
	[ORIGINAL_ASSISTANT_UPDATE_MARK]?: UpdateAssistantContent;
	updateContent: UpdateAssistantContent;
};
type AssistantMessageInternals = {
	contentContainer?: { children: unknown[] };
	lastMessage?: AssistantMessage;
};
type MarkdownInternals = {
	defaultTextStyle?: DefaultTextStyle;
	theme?: MarkdownTheme;
	invalidate?: () => void;
};

function useNormalThinkingText(component: AssistantMessageComponent): void {
	const { contentContainer } = component as unknown as AssistantMessageInternals;
	for (const child of contentContainer?.children ?? []) {
		if (!(child instanceof Markdown)) continue;

		const markdown = child as unknown as MarkdownInternals;
		if (!markdown.defaultTextStyle?.italic) continue;

		markdown.defaultTextStyle = {
			...markdown.defaultTextStyle,
			bold: false,
			italic: false,
		};
		if (markdown.theme) {
			markdown.theme = {
				...markdown.theme,
				bold: (text: string) => text,
				italic: (text: string) => text,
			};
		}
		markdown.invalidate?.();
	}
}

function addThinkingPrefix(message: AssistantMessage): AssistantMessage {
	const content = message.content.map((block) => {
		if (block.type !== "thinking" || !block.thinking.trim()) return block;

		const thinking = block.thinking
			.trim()
			.split(/\n\n+/)
			.map((paragraph) => {
				const trimmed = paragraph.trim();
				return trimmed.startsWith("∴") ? trimmed : `∴ ${trimmed}`;
			})
			.join("\n\n");

		return { ...block, thinking };
	});

	return { ...message, content };
}

function formatDuration(elapsedSeconds: number): string {
	const minutes = Math.floor(elapsedSeconds / 60);
	const seconds = elapsedSeconds % 60;
	return minutes > 0 ? `${minutes}m ${seconds}s` : `${seconds}s`;
}

function toCompletedMessage(message: string): string {
	const activeMessage = message.replace(/\.{3}$/, "");
	if (activeMessage === "Saliva build up") return "Saliva built up";

	const [verb, ...rest] = activeMessage.split(" ");
	const irregularPast: Record<string, string> = {
		Grinding: "Ground",
		Spitting: "Spat",
		Thrusting: "Thrust",
	};
	const completedVerb = irregularPast[verb] ?? (verb.endsWith("ing") ? `${verb.slice(0, -3)}ed` : verb);
	return [completedVerb, ...rest].join(" ");
}

function makeClaudeStyleFrame(message: string, frameIndex: number, elapsedSeconds: number): string {
	const characters = [...message];
	const highlightPosition = (frameIndex % (characters.length + 6)) - 3;
	const animatedMessage = characters
		.map((character, characterIndex) => {
			const distance = Math.abs(characterIndex - highlightPosition);
			const color = distance === 0 ? BRIGHT : distance <= 2 ? LIGHT : BASE;
			return colorize(character, color);
		})
		.join("");
	const spinner = CLAUDE_SPINNER[Math.floor(frameIndex / 2) % CLAUDE_SPINNER.length]!;
	const elapsed = colorize(` (${formatDuration(elapsedSeconds)})`, SUMMARY);

	return `${colorize(spinner, BASE)} ${animatedMessage}${elapsed}`;
}

const WORKING_MESSAGES = [

	"1337...",
	"Abusing...",
	"Balling...",
	"Banging...",
	"Brainfarting...",
	"Chasing semicolons...",
	"Chaturbating...",
	"Climaxxing...",
	"Cogitating...",
	"Combing...",
	"Conjuring...",
	"Connecting dots...",
	"Consulting the void...",
	"Consumating...",
	"Cracking...",
	"Cranking...",
	"Crunching...",
	"Disco-dusting...",
	"Doodling...",
	"Dripping...",
	"Drooling...",
	"Dry-humping...",
	"Ecstasising...",
	"Edging...",
	"Epanalepsing...",
	"Fapping...",
	"Fingering...",
	"Fipfapping...",
	"Flinching...",
	"Flying...",
	"Fondling...",
	"Fuzzing...",
	"Gagging...",
	"Gooning...",
	"Grinding...",
	"Guessing...",
	"Hallucinating...",
	"Handholding...",
	"Headbanging...",
	"Herding bits...",
	"Hoeing...",
	"Humping...",
	"Investigating...",
	"K00king...",
	"Klebing...",
	"Lollygagging...",
	"Lubricating...",
	"Luftschloss building...",
	"Luring...",
	"Lusering...",
	"Making shit up...",
	"Mansplaying...",
	"Moaning...",
	"Moseying...",
	"Noodling...",
	"Nose picking...",
	"Null-pointing...",
	"Percolating...",
	"Pointing...",
	"Polishing pixels...",
	"Pondering...",
	"Re-ranking...",
	"Rimming...",
	"Romanticising...",
	"Ruminating...",
	"SEOing...",
	"Saliva build up...",
	"Salivating...",
	"Schadenfreude...",
	"Scheming...",
	"Scissoring...",
	"Screwing...",
	"Scribbling...",
	"Searching...",
	"Seeking...",
	"Simulating...",
	"Slowbombing...",
	"Smashing...",
	"Sniffing...",
	"Snowballing...",
	"Snowman-building...",
	"Spamming...",
	"Spanking...",
	"Spelunking...",
	"Spitting...",
	"Stack-overflowing...",
	"Stack-smashing...",
	"Stacking...",
	"Stalking...",
	"Stretching...",
	"Sucking...",
	"Summoning electrons...",
	"Swallowing...",
	"Synecdochical searching...",
	"Syrupping...",
	"Thrusting...",
	"Tinkering...",
	"Trolling...",
	"Tweaking...",
	"Untangling...",
	"Vomiting...",
	"Yo-yo(ing)...",
	
] as const;

export default function (pi: ExtensionAPI) {
	const assistantPrototype = AssistantMessageComponent.prototype as unknown as AssistantMessagePrototype;
	assistantPrototype[ORIGINAL_ASSISTANT_UPDATE_MARK] ??= assistantPrototype.updateContent;
	const originalAssistantUpdate = assistantPrototype[ORIGINAL_ASSISTANT_UPDATE_MARK];
	assistantPrototype.updateContent = function (message) {
		originalAssistantUpdate.call(this, addThinkingPrefix(message));
		useNormalThinkingText(this);
		(this as unknown as AssistantMessageInternals).lastMessage = message;
	};

	let previousIndex = -1;
	let startedAt: number | undefined;
	let completedMessage: string | undefined;
	let animationTimer: ReturnType<typeof setInterval> | undefined;

	const stopAnimation = () => {
		if (animationTimer) {
			clearInterval(animationTimer);
			animationTimer = undefined;
		}
	};

	pi.registerEntryRenderer(DURATION_ENTRY_TYPE, (entry) => {
		const data = entry.data as { elapsedSeconds: number; completedMessage?: string };
		const summary = `✻ ${data.completedMessage ?? "Sautéed"} for ${formatDuration(data.elapsedSeconds)}`;
		return new Text(colorize(summary, SUMMARY), 1, 0);
	});

	pi.on("before_agent_start", (_event, ctx) => {
		stopAnimation();
		startedAt = Date.now();
		if (ctx.mode !== "tui") return;

		let index = Math.floor(Math.random() * WORKING_MESSAGES.length);
		if (WORKING_MESSAGES.length > 1 && index === previousIndex) {
			index = (index + 1) % WORKING_MESSAGES.length;
		}

		previousIndex = index;
		const workingMessage = WORKING_MESSAGES[index];
		completedMessage = toCompletedMessage(workingMessage);
		let frameIndex = 0;

		const updateAnimation = () => {
			const elapsedSeconds = Math.max(1, Math.floor((Date.now() - startedAt!) / 1000));
			ctx.ui.setWorkingIndicator({
				frames: [makeClaudeStyleFrame(workingMessage, frameIndex, elapsedSeconds)],
			});
			frameIndex++;
		};

		ctx.ui.setWorkingMessage("");
		updateAnimation();
		animationTimer = setInterval(updateAnimation, ANIMATION_INTERVAL_MS);
	});

	pi.on("agent_settled", () => {
		stopAnimation();
		if (startedAt === undefined || completedMessage === undefined) return;

		const elapsedSeconds = Math.max(1, Math.floor((Date.now() - startedAt) / 1000));
		pi.appendEntry(DURATION_ENTRY_TYPE, { elapsedSeconds, completedMessage });
		startedAt = undefined;
		completedMessage = undefined;
	});

	pi.on("session_shutdown", () => {
		stopAnimation();
	});
}
