import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { unlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import type { ImageContent } from "@earendil-works/pi-ai";
import { labelPastedImages } from "./pasted-image-labels.ts";

async function clipboardFile(extension: "jpg" | "png", bytes: string) {
  const path = join(tmpdir(), `pi-clipboard-${randomUUID()}.${extension}`);
  await writeFile(path, bytes);
  return path;
}

test("pasted clipboard paths become numbered labels and image attachments", async (t) => {
  const first = await clipboardFile("png", "first-image");
  const second = await clipboardFile("jpg", "second-image");
  t.after(async () => Promise.all([unlink(first), unlink(second)]));

  const result = await labelPastedImages(`Compare ${first} with ${second}.`);

  assert.equal(result?.text, "Compare [Image #1] with [Image #2].");
  assert.deepEqual(
    result?.images.map(({ data, mimeType }) => ({
      data: Buffer.from(data, "base64").toString(),
      mimeType,
    })),
    [
      { data: "first-image", mimeType: "image/png" },
      { data: "second-image", mimeType: "image/jpeg" },
    ],
  );
});

test("numbering follows images already attached to the input event", async (t) => {
  const path = await clipboardFile("png", "new-image");
  t.after(async () => unlink(path));
  const existing: ImageContent = {
    type: "image",
    data: Buffer.from("existing-image").toString("base64"),
    mimeType: "image/webp",
  };

  const result = await labelPastedImages(path, [existing]);

  assert.equal(result?.text, "[Image #2]");
  assert.deepEqual(result?.images[0], existing);
  assert.equal(result?.images[1]?.mimeType, "image/png");
});

test("missing clipboard files remain paths and do not trigger a transform", async () => {
  const missing = join(tmpdir(), `pi-clipboard-${randomUUID()}.png`);
  assert.equal(await labelPastedImages(`Inspect ${missing}`), undefined);
  assert.equal(await labelPastedImages("No pasted image here"), undefined);
});
