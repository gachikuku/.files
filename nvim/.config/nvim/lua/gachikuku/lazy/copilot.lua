return {
    {
        "zbirenbaum/copilot.lua",
        cmd = "Copilot",
        event = "InsertEnter",
        config = function()
            require("copilot").setup({
                suggestion = {
                    enabled = true,
                    auto_trigger = false,
                    hide_during_completion = false,
                    debounce = 25,
                    keymap = {
                        accept = "<C-l>",      -- Changed from false to "<C-l>" to accept the full suggestion
                        accept_word = false,
                        accept_line = "<Tab>", -- Remains unchanged
                        next = false,
                        prev = false,
                        dismiss = false,
                    },
                },
            })
        end,
    },
}
