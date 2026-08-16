import {
  UserMessageComponent,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import { Box } from "@earendil-works/pi-tui";
import { CONTENT_PADDING_X } from "./layout-padding.ts";

const PATCH_MARK = "__thinUserMessagesPatched";

type UserMessagePrototype = {
  [PATCH_MARK]?: boolean;
  rebuild(this: UserMessageComponent): void;
};

type MutableBox = Box & { paddingX: number; paddingY: number };

export default function (_pi: ExtensionAPI) {
  const prototype =
    UserMessageComponent.prototype as unknown as UserMessagePrototype;
  if (prototype[PATCH_MARK]) return;

  const originalRebuild = prototype.rebuild;
  prototype.rebuild = function () {
    originalRebuild.call(this);

    const contentBox = this.children[0];
    if (contentBox instanceof Box) {
      const mutableBox = contentBox as MutableBox;
      mutableBox.paddingX = CONTENT_PADDING_X;
      mutableBox.paddingY = 0;
      contentBox.invalidate();
    }
  };
  prototype[PATCH_MARK] = true;
}
