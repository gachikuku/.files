import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import layoutPadding from "./layout-padding.ts";
import pastedImageLabels from "./pasted-image-labels.ts";
import playfulWorkingMessage from "./playful-working-message.ts";
import thinUserMessages from "./thin-user-messages.ts";
import toolStatusStyle from "./tool-status-style.ts";

export default function (pi: ExtensionAPI) {
  layoutPadding(pi);
  pastedImageLabels(pi);
  playfulWorkingMessage(pi);
  thinUserMessages(pi);
  toolStatusStyle(pi);
}
