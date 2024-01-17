return {
    "epwalsh/obsidian.nvim",
    -- exrc security implications? 
    version = "*",  -- recommended, use latest release instead of latest commit
    lazy = true,
    ft = "markdown",
    -- replace the above line with this if you only want to load obsidian.nvim for markdown files in your vault:
    -- event = {
        --   -- if you want to use the home shortcut '~' here you need to call 'vim.fn.expand'.
        --   -- e.g. "bufreadpre " .. vim.fn.expand "~" .. "/my-vault/**.md"
        --   "bufreadpre path/to/my-vault/**.md",
        --   "bufnewfile path/to/my-vault/**.md",
        -- },
    dependencies = {
        -- required.
        "nvim-lua/plenary.nvim",
    },
    opts = {
        workspaces = {
            {
                name = "Notes",
                path = "~/Notes",
            },
        },
    },
}
