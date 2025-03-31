return {
	"vimwiki/vimwiki",
	init = function()
		vim.g.vimwiki_list = {
			{
				path = "~/iCloud/",
				syntax = "markdown",
				ext = ".md",
			},
		}
		vim.g.vimwiki_global_ext = 0
	end,
}
