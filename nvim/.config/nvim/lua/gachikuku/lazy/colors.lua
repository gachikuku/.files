function ColorMyPencils(color)
    color = color or "flexoki-dark"
    vim.cmd.colorscheme(color)

    vim.api.nvim_set_hl(0, "Normal", { bg = "NONE" })
    vim.api.nvim_set_hl(0, "NormalFloat", { bg = "NONE" })
    -- vim.api.nvim_set_hl(0, "LineNr", { bg = "NONE" })

    vim.api.nvim_set_hl(0, "StatusLine", { ctermfg = "darkgrey", ctermbg = "NONE" })
    vim.api.nvim_set_hl(0, "StatusLineNC", { ctermfg = "darkgrey", ctermbg = "NONE" })
    vim.api.nvim_set_hl(0, "MsgArea", { ctermfg = "darkgrey", ctermbg = "NONE" })
end

return {
    "kepano/flexoki-neovim",
    lazy = false,
    priority = 1000,
    config = function()
        ColorMyPencils()
    end
}
