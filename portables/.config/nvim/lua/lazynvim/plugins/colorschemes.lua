return {
  {
    "folke/tokyonight.nvim",
    priority = 1000,
    config = (vim.g.default_colorscheme == "tokyonight") and function()
      vim.cmd.colorscheme("tokyonight-night")
    end or nil,
  },
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = (vim.g.default_colorscheme == "catpuccin") and function()
      vim.cmd.colorscheme("catpuccin")
    end or nil,
  },
  {
    "rose-pine/neovim",
    name = "rose-pine",
    config = (vim.g.default_colorscheme == "rose-pine") and function()
      vim.cmd.colorscheme("rose-pine")
    end or nil,
  },
}
