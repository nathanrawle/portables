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
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    local function with_visible_preview(preview_action, fallback_action)
      return function(prompt_bufnr)
        local picker = action_state.get_current_picker(prompt_bufnr)
        local has_preview = picker
          and picker.previewer
          and picker.preview_win
          and vim.api.nvim_win_is_valid(picker.preview_win)
        if has_preview then
          preview_action(prompt_bufnr)
        elseif fallback_action then
          fallback_action(prompt_bufnr)
        end
      end
    end

    require("telescope").setup({
      defaults = {
        preview = {
          treesitter = {
            disable = { "zsh" },
          },
        },
        mappings = {
          n = {
            ["<S-h>"] = with_visible_preview(actions.preview_scrolling_left, actions.move_to_top),
            ["<S-l>"] = with_visible_preview(actions.preview_scrolling_right, actions.move_to_bottom),
            ["<S-j>"] = with_visible_preview(actions.preview_scrolling_down, actions.move_selection_next),
            ["<S-k>"] = with_visible_preview(actions.preview_scrolling_up, actions.move_selection_previous),
          },
          i = {
            ["<M-h>"] = with_visible_preview(actions.preview_scrolling_left, actions.nop),
            ["<M-l>"] = with_visible_preview(actions.preview_scrolling_right, actions.nop),
            ["<M-j>"] = with_visible_preview(actions.preview_scrolling_down, actions.nop),
            ["<M-k>"] = with_visible_preview(actions.preview_scrolling_up, actions.results_scrolling_right),
          },
        },
      },
      pickers = {
        buffers = {
          attach_mappings = function(prompt_bufnr, map)
            vim.keymap.del({ "i", "n" }, "<M-d>", { buffer = prompt_bufnr })
            map({ "i", "n" }, "<C-b>", actions.delete_buffer)
            return true
          end,
        },
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
