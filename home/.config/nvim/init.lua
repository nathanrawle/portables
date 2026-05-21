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
  "make",
  "cmake",
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

vim.filetype.add({
  extension = {
    tf = "terraform",
    tfvars = "terraform-vars",
  },
  filename = {
    ["compose.yaml"] = "yaml.docker-compose",
    ["compose.yml"] = "yaml.docker-compose",
    ["docker-compose.yaml"] = "yaml.docker-compose",
    ["docker-compose.yml"] = "yaml.docker-compose",
  },
  pattern = {
    [".*/%.forgejo/workflows/.*%.ya?ml"] = "yaml.ghaction",
    [".*/%.gitea/workflows/.*%.ya?ml"] = "yaml.ghaction",
    [".*/%.github/workflows/.*%.ya?ml"] = "yaml.ghaction",
  },
})

vim.g.mason_lsp_ensure_installed = {
  "bash-language-server",
  "docker-compose-language-service",
  "docker-language-server",
  "gh-actions-language-server",
  "gopls",
  "lua-language-server",
  "ruff",
  "taplo",
  "terraform-ls",
  "typescript-language-server",
  "yaml-language-server",
}
vim.g.mason_tool_ensure_installed = {
  "actionlint",
  "sqlfluff",
  "stylua", -- Used to format Lua code
  "terraform",
}
vim.g.never_show = {
  ".DS_Store",
  ".terraform/",
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
