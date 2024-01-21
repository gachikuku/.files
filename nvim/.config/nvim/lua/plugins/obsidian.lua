return {
    "epwalsh/obsidian.nvim",
    lazy = true,
    version = "*",
    ft = "markdown",
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
    attachments = {
        img_folder = ".assets/imgs",
    },
}
