return {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
        local harpoon = require("harpoon")
        -- REQUIRED
        harpoon:setup()
        -- REQUIRED

        vim.keymap.set("n", "<leader>a", function() harpoon:list():append() end)
        vim.keymap.set("n", "<C-h>", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end)

        --[[ I find it, it interferes with many keybindings so keeping simple
        vim.keymap.set("n", "<C-j>", function() harpoon:list():select(1) end)
        vim.keymap.set("n", "<C-k>", function() harpoon:list():select(2) end)
        vim.keymap.set("n", "<C-l>", function() harpoon:list():select(3) end)
        ]]--

        vim.keymap.set("n", "<C-e>", function() harpoon:list():prev() end)
        vim.keymap.set("n", "<C-n>", function() harpoon:list():next() end)
    end
}
