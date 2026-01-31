vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.g.have_nerd_font = true
vim.g.default_colorscheme = "tokyonight"
vim.g.ts_ensure_installed = {
  "bash",
  "c",
  "csv",
  "diff",
  "dockerfile",
  "editorconfig",
  "go",
  "hcl",
  "html",
  "ini",
  "javascript",
  "jinja",
  "json",
  "lua",
  "luadoc",
  "markdown",
  "markdown_inline",
  "python",
  "query",
  "regex",
  "requirements",
  "sql",
  "terraform",
  "toml",
  "vim",
  "vimdoc",
  "yaml",
  "zsh",
}
vim.g.lsp_ensure_installed = {
  "actionlint",
  "bash-language-server",
  "docker-compose-language-service",
  "docker-language-server",
  "gh-actions-language-server",
  "gopls",
  "ltex-ls-plus",
  "lua-language-server",
  "ruff",
  "sqls",
  "sqruff",
  "stylua", -- Used to format Lua code
  "taplo",
  "terraform",
  "terraform-ls",
  "typescript-language-server",
  "yaml-language-server",
}
vim.g.never_show = {
  ".DS_Store",
}
vim.g.picker_no_show = vim.list_extend({
  ".git/",
  ".venv/",
  "node_modules/",
}, vim.g.never_show)

require("netrwopts")
require("options")
require("autocommands")
require("lazynvim.init")
require("keymaps")
