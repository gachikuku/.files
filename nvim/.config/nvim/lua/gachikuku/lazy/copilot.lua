return {
    'github/copilot.vim',
    event = 'BufEnter',
    config = function()
        -- Map common Copilot commands
        vim.keymap.set('i', '<C-l>', 'copilot#Accept("<CR>")', {
            expr = true,
            replace_keycodes = false
        })

        -- vim.keymap.set('i', '<C-]>', '<Plug>(copilot-next)', { silent = true })
        -- vim.keymap.set('i', '<C-[>', '<Plug>(copilot-previous)', { silent = true })
        -- vim.keymap.set('i', '<C-\\>', '<Plug>(copilot-dismiss)', { silent = true })

        -- Some useful Copilot settings
        vim.g.copilot_no_tab_map = true
        vim.g.copilot_assume_mapped = true
        vim.g.copilot_tab_fallback = ""
		-- Disable copilot by default
		vim.g.copilot_enabled = false
    end
}
