function ColorMyPencils(color)
	color = color or "flexoki-dark"
	vim.cmd.colorscheme(color)

	vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
	vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
	--vim.api.nvim_set_hl(0, "LineNr", { bg = "none" })

end

return {

    "kepano/flexoki-neovim",

    lazy = false,
    priority = 1000,

    config = function()

        ColorMyPencils()

    end
}
