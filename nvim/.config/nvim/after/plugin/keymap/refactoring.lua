local Remap = require("gachikuku.keymap")
local nnoremap = Remap.nnoremap

nnoremap("<leader>ri", function()
    require("refactoring").refactor("Inline Variable")
end);
