return {
  "hat0uma/csvview.nvim",
  ft = { "csv", "tsv" },
  cmd = { "CsvViewEnable", "CsvViewDisable", "CsvViewToggle", "CsvViewInfo" },
  ---@module "csvview"
  ---@type CsvView.Options
  opts = {
    parser = {
      comments = { "#", "//" },
    },
    view = {
      display_mode = "border",
      header_lnum = true,
      sticky_header = {
        enabled = true,
      },
    },
    keymaps = {
      -- Text objects for selecting fields.
      textobject_field_inner = { "if", mode = { "o", "x" } },
      textobject_field_outer = { "af", mode = { "o", "x" } },

      -- Excel-like navigation.
      jump_next_field_end = { "<Tab>", mode = { "n", "v" } },
      jump_prev_field_end = { "<S-Tab>", mode = { "n", "v" } },
      jump_next_row = { "<Enter>", mode = { "n", "v" } },
      jump_prev_row = { "<S-Enter>", mode = { "n", "v" } },
    },
  },
  config = function(_, opts)
    require("csvview").setup(opts)

    local function set_csv_highlights()
      local syntax_links = {
        csvCol1 = "Statement",
        csvCol2 = "Constant",
        csvCol3 = "Type",
        csvCol4 = "PreProc",
        csvCol5 = "Identifier",
        csvCol6 = "Special",
        csvCol7 = "String",
        csvCol8 = "Comment",
        escCsvCol1 = "csvCol1",
        escCsvCol2 = "csvCol2",
        escCsvCol3 = "csvCol3",
        escCsvCol4 = "csvCol4",
        escCsvCol5 = "csvCol5",
        escCsvCol6 = "csvCol6",
        escCsvCol7 = "csvCol7",
        escCsvCol8 = "csvCol8",
      }

      -- Match Neovim's syntax/csv.vim defaults; it intentionally has no csvCol0 link.
      for name, link in pairs(syntax_links) do
        vim.api.nvim_set_hl(0, name, { link = link, default = true })
      end
    end

    set_csv_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("user_csvview_highlights", { clear = true }),
      callback = set_csv_highlights,
    })

    local function enable(buf)
      if vim.b[buf].csvview_auto_enable_pending then
        return
      end

      vim.b[buf].csvview_auto_enable_pending = true
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end

        vim.b[buf].csvview_auto_enable_pending = nil
        local csvview = require("csvview")
        if not csvview.is_enabled(buf) then
          csvview.enable(buf)
        end
      end)
    end

    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("user_csvview", { clear = true }),
      pattern = { "csv", "tsv" },
      callback = function(args)
        enable(args.buf)
      end,
    })

    if vim.bo.filetype == "csv" or vim.bo.filetype == "tsv" then
      enable(0)
    end
  end,
}
