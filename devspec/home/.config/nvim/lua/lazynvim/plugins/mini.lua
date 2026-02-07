return { -- Collection of various small independent plugins/modules
  "nvim-mini/mini.nvim",
  config = function()
    -- Better Around/Inside textobjects
    require("mini.ai").setup({ n_lines = 500 })

    -- Add/delete/replace surroundings (brackets, quotes, etc.)
    require("mini.surround").setup({
      mappings = {
        add = "+a", -- Add surrounding in Normal and Visual modes
        delete = "-s", -- Delete surrounding
        find = "gs", -- Find surrounding (to the right)
        find_left = "gS", -- Find surrounding (to the left)
        -- highlight = "<leader>h", -- Highlight surrounding
        replace = "cs", -- Replace surrounding

        suffix_last = "p", -- Suffix to search with "prev" method
        suffix_next = "n", -- Suffix to search with "next" method
      },
    })

    local statusline = require("mini.statusline")
    statusline.setup({ use_icons = vim.g.have_nerd_font })
    ---@diagnostic disable-next-line: duplicate-set-field
    statusline.section_location = function()
      return "%2l:%-2v"
    end
  end,
}
