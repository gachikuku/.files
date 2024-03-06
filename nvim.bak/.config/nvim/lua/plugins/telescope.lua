return {
   "nvim-telescope/telescope.nvim",
    config = function()
        local builtin = require('telescope.builtin')
        vim.keymap.set('n', '<leader>fi', builtin.find_files, {})
        vim.keymap.set('n', '<leader>lg', builtin.live_grep, {})
        vim.keymap.set('n', '<leader>ht', builtin.help_tags, {})
        vim.keymap.set('n', '<C-p>', builtin.git_files, {})
        -- How to telescope back to nvim dotfiles with "dt" ?
    end,
}
