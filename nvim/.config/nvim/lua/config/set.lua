vim.opt.guicursor = ""

-- vim.opt.nu = true
-- vim.opt.relativenumber = true

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

vim.opt.smartindent = true

vim.opt.wrap = false

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true

vim.opt.hlsearch = false
vim.opt.incsearch = true

vim.opt.termguicolors = true

-- see <C-d>, <C-u> remap 
-- vim.opt.scrolloff = 8

vim.opt.isfname:append("@-@")

vim.opt.updatetime = 50

-- This can have security implications
vim.opt.exrc = true

-- Extra tight for netiquette
vim.opt.colorcolumn = "73"
vim.opt.winheight = 9999

-- clearing up the netrw view
vim.g.netrw_browse_split = 0
vim.g.netrw_banner = 0
vim.g.netrw_winsize = 25

-- see hidden chars and their colors
-- Seen IppSec using for hidden chars
-- vim.o.list = true
vim.opt.listchars = { 
	tab = "| ",
	eol = "¬",
	trail = "·",
}

-- greek spelling
vim.opt.spelllang = "el"

-- jcs influence? 
vim.opt.completeopt = "preview"
vim.opt.signcolumn = "no"
