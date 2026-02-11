local my_utils = require("utils")
return {
  "nvim-telescope/telescope.nvim",
  event = "VimEnter",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope-ui-select.nvim",
    { "nvim-tree/nvim-web-devicons", enabled = vim.g.have_nerd_font },
    {
      "nvim-telescope/telescope-fzf-native.nvim",
      build = "make",
      cond = function()
        return vim.fn.executable("make") == 1
      end,
    },
  },
  config = function()
    require("telescope").setup({
      defaults = {
        preview = {
          treesitter = {
            disable = { "zsh" },
          },
        },
      },
      pickers = {
        find_files = {
          find_command = function(_)
            local cmd_list = { "fd", "--type", "f", "--color", "never" }
            local exclusion_list = my_utils.repeat_flag_with_args("--exclude", vim.g.picker_no_show)
            return vim.list_extend(cmd_list, exclusion_list)
          end,
          hidden = true,
          no_ignore = true,
        },
        live_grep = {
          additional_args = {
            "--hidden",
            "--no-ignore",
          },
          glob_pattern = (function()
            local pats = {}
            for _, v in ipairs(vim.g.picker_no_show) do
              pats[#pats + 1] = "!" .. v
            end
            return pats
          end)(),
        },
        help_tags = {
          attach_mappings = function(prompt_bufnr, _)
            local actions = require("telescope.actions")
            local action_state = require("telescope.actions.state")
            local fh = require("floating-help")
            actions.select_default:replace(function()
              actions.close(prompt_bufnr)
              local entry = action_state.get_selected_entry()
              if entry then
                fh.open(entry.value)
              end
            end)
            return true
          end,
        },
      },
      extensions = {
        ["ui-select"] = {
          require("telescope.themes").get_dropdown(),
        },
      },
    })

    pcall(require("telescope").load_extension, "fzf")
    pcall(require("telescope").load_extension, "ui-select")

    local builtin = require("telescope.builtin")
    vim.keymap.set("n", "<leader>sh", builtin.help_tags, { desc = "Search Help" })
    vim.keymap.set("n", "<leader>sk", builtin.keymaps, { desc = "Search Keymaps" })
    vim.keymap.set("n", "<leader>sf", builtin.find_files, { desc = "Search Files" })
    vim.keymap.set("n", "<leader>ss", builtin.builtin, { desc = "Search Select Telescope" })
    vim.keymap.set("n", "<leader>sw", builtin.grep_string, { desc = "Search current Word" })
    vim.keymap.set("n", "<leader>sg", builtin.live_grep, { desc = "Search by Grep" })
    vim.keymap.set("n", "<leader>sd", builtin.diagnostics, { desc = "Search Diagnostics" })
    vim.keymap.set("n", "<leader>sr", builtin.resume, { desc = "Search Resume" })
    vim.keymap.set("n", "<leader>s.", builtin.oldfiles, { desc = 'Search Recent Files ("." for repeat)' })
    vim.keymap.set("n", "<leader><leader>", builtin.buffers, { desc = "Find existing buffers" })

    vim.keymap.set("n", "<leader>uC", builtin.colorscheme, { desc = "UI: View Colorschemes" })

    vim.keymap.set("n", "<leader>/", function()
      builtin.current_buffer_fuzzy_find(require("telescope.themes").get_dropdown({
        winblend = 10,
        previewer = false,
      }))
    end, { desc = "Fuzzy search in current buffer" })

    vim.keymap.set("n", "<leader>s/", function()
      builtin.live_grep({
        grep_open_files = true,
        prompt_title = "Live Grep in Open Files",
      })
    end, { desc = "Search in Open Files" })

    vim.keymap.set("n", "<leader>sn", function()
      builtin.find_files({ cwd = vim.fn.stdpath("config") })
    end, { desc = "Search Neovim files" })
  end,
}
