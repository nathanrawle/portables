return {

  "NMAC427/guess-indent.nvim", -- Detect tabstop and shiftwidth automatically

  -- Adds git related signs to the gutter, as well as utilities for managing changes
  "lewis6991/gitsigns.nvim",

  {
    "folke/todo-comments.nvim",
    enable = false,
    event = "VimEnter",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = { signs = false },
  },
}
