return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  lazy = false,
  build = ":TSUpdate",

  config = function()
    local TS = require("nvim-treesitter")

    vim.treesitter.language.register("terraform", "tf")

    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("user_treesitter_parsers", { clear = true }),
      pattern = "TSUpdate",
      callback = function()
        local parsers = require("nvim-treesitter.parsers")

        -- Generated artifacts live on main; the default master branch omits parser.c.
        parsers.tmux = {
          install_info = {
            url = "https://github.com/Freed-Wu/tree-sitter-tmux",
            branch = "main",
            revision = "26c21424955a719bfdbb3f595265a5322200c261",
            queries = "queries",
          },
          requires = { "tmuxf" },
          tier = 2,
        }
        parsers.tmuxf = {
          install_info = {
            url = "https://github.com/Freed-Wu/tree-sitter-tmuxf",
            branch = "main",
            revision = "bd9a418491422a11ffc4d2760cebaafd29fe173f",
            queries = "queries",
          },
          tier = 2,
        }
      end,
    })

    TS.install(vim.g.ts_ensure_installed or {})

    local indent_disabled = {
      -- Let language-native indent/formatters own these if TS indent annoys you.
      -- python = true,
      -- yaml = true,
    }

    local valid_strategies = {
      treesitter = true,
      regex = true,
      both = true,
    }

    local function enable_regex_highlighting(bufnr)
      vim.treesitter.stop(bufnr)
      vim.bo[bufnr].syntax = "ON"
    end

    local function highlighting_strategy(lang)
      local configured = vim.g.syntax_highlight_strategy
      if configured == nil then
        return "treesitter", false
      end

      if type(configured) ~= "table" then
        vim.notify_once("vim.g.syntax_highlight_strategy must be a table; using treesitter", vim.log.levels.WARN)
        return "treesitter", false
      end

      local strategy = configured[lang]
      if strategy == nil then
        return "treesitter", false
      end

      if valid_strategies[strategy] then
        return strategy, true
      end

      vim.notify_once(
        ("Invalid syntax highlighting strategy for %s: %s; using treesitter"):format(lang, vim.inspect(strategy)),
        vim.log.levels.WARN
      )
      return "treesitter", true
    end

    local function fallback_to_regex(bufnr, lang, reason)
      enable_regex_highlighting(bufnr)
      vim.notify_once(
        ("Tree-sitter highlighting unavailable for %s; using regex syntax: %s"):format(lang, reason),
        vim.log.levels.WARN
      )
    end

    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("user_treesitter", { clear = true }),
      callback = function(ev)
        local bufnr = ev.buf
        local ft = vim.bo[bufnr].filetype
        local lang = vim.treesitter.language.get_lang(ft)

        if not lang then
          return
        end

        local strategy, explicitly_configured = highlighting_strategy(lang)
        if strategy == "regex" then
          enable_regex_highlighting(bufnr)
          return
        end

        vim.treesitter.stop(bufnr)

        local parser_available, parser_error = vim.treesitter.language.add(lang)
        if not parser_available then
          if explicitly_configured then
            fallback_to_regex(bufnr, lang, parser_error)
          else
            enable_regex_highlighting(bufnr)
          end
          return
        end

        local query_ok, highlight_query = pcall(vim.treesitter.query.get, lang, "highlights")
        if not query_ok or not highlight_query then
          local reason = query_ok and "missing highlights query" or tostring(highlight_query)
          fallback_to_regex(bufnr, lang, reason)
          return
        end

        local start_ok, start_error = pcall(vim.treesitter.start, bufnr, lang)
        if not start_ok then
          fallback_to_regex(bufnr, lang, tostring(start_error))
          return
        end

        if strategy == "both" then
          vim.bo[bufnr].syntax = "ON"
        end

        local indent_ok, indent_query = pcall(vim.treesitter.query.get, lang, "indents")
        if not indent_disabled[lang] and indent_ok and indent_query then
          vim.bo[bufnr].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
      end,
    })
  end,
}
