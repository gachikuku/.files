import type { ImageContent } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const MIME_TYPES = {
  gif: "image/gif",
  jpeg: "image/jpeg",
  jpg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
} as const;

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function clipboardImagePattern(): RegExp {
  const prefix = escapeRegExp(join(tmpdir(), "pi-clipboard-"));
  return new RegExp(
    `${prefix}[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\.(png|jpe?g|gif|webp)`,
    "gi",
  );
}

export async function labelPastedImages(
  text: string,
  existingImages: ImageContent[] = [],
): Promise<{ text: string; images: ImageContent[] } | undefined> {
  const matches = [...text.matchAll(clipboardImagePattern())];
  if (matches.length === 0) return undefined;

  const images = [...existingImages];
  let transformed = "";
  let cursor = 0;
  let attached = 0;

  for (const match of matches) {
    const filePath = match[0];
    const index = match.index;
    const extension = match[1]?.toLowerCase() as keyof typeof MIME_TYPES;

    transformed += text.slice(cursor, index);
    try {
      const data = await readFile(filePath);
      images.push({
        type: "image",
        data: data.toString("base64"),
        mimeType: MIME_TYPES[extension],
      });
      attached += 1;
      transformed += `[Image #${existingImages.length + attached}]`;
    } catch {
      // Keep the path intact if the temporary clipboard file disappeared.
      transformed += filePath;
    }
    cursor = index + filePath.length;
  }

  if (attached === 0) return undefined;
  transformed += text.slice(cursor);
  return { text: transformed, images };
}

export default function (pi: ExtensionAPI) {
  pi.on("input", async (event) => {
    if (event.source !== "interactive") return { action: "continue" };

    const transformed = await labelPastedImages(event.text, event.images);
    if (!transformed) return { action: "continue" };

    return { action: "transform", ...transformed };
  });
}
