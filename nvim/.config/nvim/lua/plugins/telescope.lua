return {
   "nvim-telescope/telescope.nvim",
    config = function()
        local builtin = require('telescope.builtin')
        vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
        vim.keymap.set('n', '<leader>lg', builtin.live_grep, {})
        vim.keymap.set('n', '<leader>ht', builtin.help_tags, {})
        -- How to telescope back to nvim dotfiles with "dt" ?
    end,
}
