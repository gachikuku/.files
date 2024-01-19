return {
    "rebelot/kanagawa.nvim",
    lazy = false, -- make sure we load this during startup if it is your main colorscheme
    priority = 1000, -- make sure to load this before all the other start plugins
    config = function()
        require("kanagawa").setup({
            transparent = true,
            colors = {
                theme = {
                    all = {
                        ui = {
                            bg_gutter = "#F4F0E3"
                        }
                    }
                }
            },
        })
        -- load the colorscheme here
        vim.cmd("colorscheme kanagawa-lotus")
    end,
}


-- https://github.com/ThePrimeagen/init.lua/issues/108 
