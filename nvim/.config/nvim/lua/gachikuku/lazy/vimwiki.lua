return {
	"vimwiki/vimwiki",
	init = function()
		vim.g.vimwiki_list = {
			{
				path = "~/iCloud/",
				ext = ".md",
				-- automatically enable VimwikiDiaryGenerateLinks
				-- when opening a diary file
				-- it's an open issue `https://github.com/vimwiki/vimwiki/issues/1055`
				auto_diary_index = 1,

				syntax = "markdown",
			},
		}
		vim.g.vimwiki_global_ext = 0
	end,
}
