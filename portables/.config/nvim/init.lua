vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
vim.g.have_nerd_font = true
vim.g.default_colorscheme = "tokyonight"
vim.g.ts_ensure_installed = {
  "bash",
  "c",
  "diff",
  "html",
  "hcl",
  "lua",
  "luadoc",
  "markdown",
  "markdown_inline",
  "python",
  "query",
  "vim",
  "vimdoc",
}

require("options")
require("keymaps")
require("autocommands")

require("lazynvim.init")
