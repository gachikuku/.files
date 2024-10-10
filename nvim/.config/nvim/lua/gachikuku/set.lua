vim.opt.guicursor = ""

vim.opt.nu = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.smartindent = true

vim.opt.wrap = false

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true

vim.opt.hlsearch = false
vim.opt.incsearch = true

vim.opt.termguicolors = true

vim.opt.isfname:append("@-@")

vim.opt.updatetime = 50

vim.opt.colorcolumn = "80"

vim.api.nvim_set_hl(0, "CmpItemKindCody", { fg = "Red" })

-- ddvault 
vim.opt.listchars = { tab = '▸ ', eol = '¬', space = '.' }
-- :set list no :set listchar


-- need custom vimrcs
vim.o.exrc = true
vim.o.secure = true

-- case insesitive search?
vim.opt.ignorecase = true
