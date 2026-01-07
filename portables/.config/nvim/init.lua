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
  "terraform",
  "vim",
  "vimdoc",
}
vim.g.lsp_ensure_installed = {
  "stylua", -- Used to format Lua code
  "ruff",
  "terraform-ls",
  "gh-actions-language-server",
  "actionlint",
}

require("options")
require("keymaps")
require("autocommands")

require("lazynvim.init")
