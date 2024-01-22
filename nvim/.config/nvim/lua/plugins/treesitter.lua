return {
    "nvim-treesitter/nvim-treesitter",
    ensure_installed = {
        "javascript",
        "c",
        "lua",
        "python",
        "go"
    },
    -- Install parsers synchronously (only applied to `ensure_installed`)
    sync_install = false,
    auto_install = true,
    highlight = {
        -- `false` will disable the whole extension
        enable = true,
        additional_vim_regex_highlighting = false,
    },
    vim.filetype.add({
        extension = {
            templ = "templ",
        },
    })
}
