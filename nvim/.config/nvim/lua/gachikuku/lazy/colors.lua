function ColorMyPencils(color)
    color = color or "flexoki-light"
    vim.cmd.colorscheme(color)
    vim.api.nvim_set_hl(0, "Normal", { bg = "NONE" })
    vim.api.nvim_set_hl(0, "NormalFloat", { bg = "NONE" })
    -- vim.api.nvim_set_hl(0, "LineNr", { bg = "NONE" })
    vim.api.nvim_set_hl(0, "StatusLine", { fg = "grey", bg = "NONE" })
    vim.api.nvim_set_hl(0, "StatusLineNC", { fg = "grey", bg = "NONE" })
    vim.api.nvim_set_hl(0, "MsgArea", { fg = "grey", bg = "NONE" })
end

return {
    "kepano/flexoki-neovim",
    name = "flexoki",
    lazy = false,
    priority = 1000,
    config = function()
        require("flexoki").setup({
            variant = "light", -- This ensures light variant
            styles = {
                transparency = false,
            },
        })
        ColorMyPencils("flexoki-light")
    end
}
