return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  lazy = false,
  build = ":TSUpdate",

  config = function()
    local TS = require("nvim-treesitter")

    TS.install(vim.g.ts_ensure_installed or {})

    local indent_disabled = {
      -- Let language-native indent/formatters own these if TS indent annoys you.
      -- python = true,
      -- yaml = true,
    }

    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("user_treesitter", { clear = true }),
      callback = function(ev)
        local bufnr = ev.buf
        local ft = vim.bo[bufnr].filetype
        local lang = vim.treesitter.language.get_lang(ft)

        if not lang then
          return
        end

        if not pcall(vim.treesitter.start, bufnr, lang) then
          return
        end

        if not indent_disabled[lang] then
          vim.bo[bufnr].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
      end,
    })
  end,
}
