-- A private, read-only scrollback viewer. All customization is native Lua.
-- Launched without plugins or the user's Neovim configuration.
for _, provider in ipairs({ "python3", "ruby", "node", "perl" }) do
  vim.g["loaded_" .. provider .. "_provider"] = 0
end
vim.g.did_load_filetypes = 1
vim.g.did_load_ftplugin = 1
vim.g.did_indent_on = 1
vim.g.skip_defaults_vim = 1

local options = {
  loadplugins = false, modeline = false, modelines = 0, exrc = false,
  readonly = true, modifiable = false, write = false,
  swapfile = false, backup = false, writebackup = false, undofile = false,
  shada = "", history = 0, clipboard = "",
  number = false, relativenumber = false, signcolumn = "no", foldcolumn = "0",
  wrap = true, linebreak = true, breakindent = true,
  laststatus = 2, showtabline = 0, showmode = false, showcmd = false, ruler = false,
  incsearch = true, hlsearch = true, ignorecase = true, smartcase = true,
  selection = "inclusive", virtualedit = "block", mouse = "", more = false,
  belloff = "all", ttimeout = true, ttimeoutlen = 50,
  background = "light", termguicolors = true, fillchars = "eob: ",
  statusline = " COPY | v/V/^V select | y/Enter copy | q exit %=%l/%L ",
}
for name, value in pairs(options) do vim.opt[name] = value end

local colors = {
  Normal = { fg = "#100f0f", bg = "#fffcf0" },
  Visual = { fg = "#100f0f", bg = "#e6e4d9" },
  StatusLine = { fg = "#6f6e69", bg = "#f2f0e5" },
  StatusLineNC = { fg = "#6f6e69", bg = "#f2f0e5" },
  NonText = { fg = "#b7b5ac", bg = "#fffcf0" },
  EndOfBuffer = { fg = "#fffcf0", bg = "#fffcf0" },
  Search = { fg = "#100f0f", bg = "#f1d37c" },
  IncSearch = { fg = "#100f0f", bg = "#e6e4d9" },
}
for name, color in pairs(colors) do vim.api.nvim_set_hl(0, name, color) end

local group = vim.api.nvim_create_augroup("RexCopyMode", { clear = true })
local pending_yank
vim.api.nvim_create_autocmd("TextYankPost", {
  group = group,
  callback = function()
    if pending_yank == nil then return end
    local was_visual = pending_yank
    pending_yank = nil
    -- A process argv plus stdin preserves terminal text literally, including
    -- linewise newlines. The override is used by tests instead of the clipboard.
    local argv = vim.g.rex_copy_command or { "/usr/bin/pbcopy" }
    local ok, result = pcall(function()
      return vim.system(argv, { stdin = vim.fn.getreg('"') }):wait(2000)
    end)
    if ok and result.code == 0 then
      vim.api.nvim_echo({ { "Copied" } }, false, {})
      return
    end
    if was_visual then vim.api.nvim_feedkeys("gv", "n", false) end
    vim.api.nvim_echo({ { "Clipboard copy failed. Press y to retry, or Esc then q to exit.",
      "ErrorMsg" } }, true, {})
  end,
})

local function copy_keys(visual)
  return function()
    pending_yank = visual
    return visual and "y" or "yy"
  end
end
for _, key in ipairs({ "y", "<CR>" }) do
  vim.keymap.set("n", key, copy_keys(false), { expr = true, silent = true })
  vim.keymap.set("x", key, copy_keys(true), { expr = true, silent = true })
end
for key, movement in pairs({ j = "gj", k = "gk", ["<Down>"] = "gj", ["<Up>"] = "gk" }) do
  vim.keymap.set({ "n", "x" }, key, movement, { silent = true })
end
vim.keymap.set("n", "<Space>", "v")
local function quit() vim.api.nvim_cmd({ cmd = "qa", bang = true }, {}) end
vim.keymap.set("n", "q", quit, { silent = true })
vim.keymap.set("n", "<Esc>", quit, { silent = true })
vim.keymap.set("x", "<Esc>", "<Esc>", { silent = true })

vim.api.nvim_create_autocmd("VimEnter", {
  group = group,
  once = true,
  callback = function()
    vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(0), 0 })
    vim.api.nvim_feedkeys("zb", "n", false)
  end,
})

-- Only snapshots in our private cache may trigger lifecycle cleanup. A normal
-- quit restores the source pane; a signal-driven close must not call the server
-- while Rex may be holding its layer lock. The block_closed handler cleans that.
local home = vim.env.HOME
local prefix = home .. "/.cache/rex-copy-mode/"
local file = vim.fn.argv(0)
local directory = file:match("^(.*)/scrollback%.txt$")
if directory and directory:sub(1, #prefix) == prefix
    and directory:sub(#prefix + 1):match("^snapshot%-[%w]+$") then
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    once = true,
    callback = function()
      if vim.v.dying ~= 0 then return end
      local rex_cli = "/Applications/Rex Beta.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"
      pcall(function()
        vim.system({ rex_cli, "--autostart=false", "do", home .. "/.config/rex/copy-cleanup.lua",
          "directory=" .. directory }):wait(5000)
      end)
    end,
  })
end
