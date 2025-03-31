return {
	"vimwiki/vimwiki",
	init = function()
		-- Define your Vimwiki settings
		vim.g.vimwiki_list = {
			{
				path = "~/iCloud/",  -- Where your wiki files are stored
				syntax = "markdown",          -- Use Markdown syntax
				ext = ".md",                   -- File extension for wiki files
			},
		}
	end,
}
