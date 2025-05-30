require("gachikuku.set")
require("gachikuku.remap")

require("gachikuku.lazy_init")

local augroup = vim.api.nvim_create_augroup
local gachikukuGroup = augroup('gachikuku', {})

local autocmd = vim.api.nvim_create_autocmd
local yank_group = augroup('HighlightYank', {})

function R(name)
    require("plenary.reload").reload_module(name)
end

vim.filetype.add({
    extension = {
        templ = 'templ',
    }
})

autocmd('TextYankPost', {
    group = yank_group,
    pattern = '*',
    callback = function()
        vim.highlight.on_yank({
            higroup = 'IncSearch',
            timeout = 40,
        })
    end,
})

autocmd('LspAttach', {
    group = gachikukuGroup,
    callback = function(e)
        local opts = { buffer = e.buf }
        vim.keymap.set("n", "gd", function() vim.lsp.buf.definition() end, opts)
        vim.keymap.set("n", "K", function() vim.lsp.buf.hover() end, opts)
        vim.keymap.set("n", "<leader>vws", function() vim.lsp.buf.workspace_symbol() end, opts)
        vim.keymap.set("n", "<leader>vd", function() vim.diagnostic.open_float() end, opts)
        vim.keymap.set("n", "<leader>vca", function() vim.lsp.buf.code_action() end, opts)
        vim.keymap.set("n", "<leader>vrr", function() vim.lsp.buf.references() end, opts)
        vim.keymap.set("n", "<leader>vrn", function() vim.lsp.buf.rename() end, opts)
        vim.keymap.set("i", "<C-h>", function() vim.lsp.buf.signature_help() end, opts)
        vim.keymap.set("n", "[d", function() vim.diagnostic.goto_next() end, opts)
        vim.keymap.set("n", "]d", function() vim.diagnostic.goto_prev() end, opts)
    end
})

--- Need this for mitmproxy
vim.api.nvim_create_augroup("MitmproxySettings", { clear = true })
vim.api.nvim_create_autocmd({"BufNewFile", "BufRead"}, {
  pattern = "mitmproxy*",
  group = "MitmproxySettings",
  callback = function()
	--- I DON'T WANT NEW LINE WHEN I EDIT A REQUEST
	vim.opt.wrap   = true
	vim.opt.binary = true
	vim.opt.eol    = false
	vim.opt.list   = true
  end
})

-- Add this to your init.lua
vim.api.nvim_create_autocmd("BufWinEnter", {
  pattern = "*",
  callback = function()
    vim.opt_local.formatoptions:remove({ "n", "r", "q", "l", "c", "j", "t" })
  end,
  group = vim.api.nvim_create_augroup("PersistentFormatOptions", { clear = true }),
})

vim.g.netrw_browse_split = 0
vim.g.netrw_banner = 0
vim.g.netrw_winsize = 25
