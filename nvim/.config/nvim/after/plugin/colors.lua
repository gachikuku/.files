require('rose-pine').setup({
    variant = 'dawn',
    light_variant = 'main',
    disable_background = true,
    highlight_groups = {
        -- Consistent with jcs theme
		StatusLine = { bg = "#444444", fg = "#f4f0dc"  },
		StatusLineNC = { bg = "#444444", fg = "#f4f0dc", blend = 33  }
	},
})

vim.cmd('colorscheme rose-pine')
