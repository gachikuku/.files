return {
    "rebelot/kanagawa.nvim",
    config = function()
        require("kanagawa").setup({
            lazy = false, -- make sure we load this during startup if it is your main colorscheme
            priority = 1000, -- make sure to load this before all the other start plugins
            transparent = true,
            colors = {
                theme = {
                    all = {
                        ui = {
                            bg_gutter = "none"
                        }
                    }
                }
            },
        })
        -- load the colorscheme here
        vim.cmd("colorscheme kanagawa-wave")
    end,
}

-- https://github.com/ThePrimeagen/init.lua/issues/108 
