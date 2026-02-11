return {
  "ThePrimeagen/harpoon",
  event = "VimEnter",
  branch = "harpoon2",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    local harpoon = require("harpoon")
    harpoon:setup()

    -- UI
    vim.keymap.set("n", "§", function()
      harpoon.ui:toggle_quick_menu(harpoon:list())
    end)

    -- add/remove
    vim.keymap.set("n", "<M-+>", function()
      harpoon:list():add()
    end, { desc = "Add to Harpoon list" })
    vim.keymap.set("n", "<M-_>", function()
      harpoon:list():remove()
    end, { desc = "Remove from Harpoon list" })

    -- select Harpoon item
    vim.keymap.set("n", "<M-j>", function()
      harpoon:list():select(1)
    end)
    vim.keymap.set("n", "<M-k>", function()
      harpoon:list():select(2)
    end)
    vim.keymap.set("n", "<M-l>", function()
      harpoon:list():select(3)
    end)
    vim.keymap.set("n", "<M-;>", function()
      harpoon:list():select(4)
    end)

    -- replace Harpoon item
    vim.keymap.set("n", "<M-J>", function()
      harpoon:list():replace_at(1)
    end, { desc = "Add to Harpoon list (index 1)" })
    vim.keymap.set("n", "<M-K>", function()
      harpoon:list():replace_at(2)
    end, { desc = "Add to Harpoon list (index 2)" })
    vim.keymap.set("n", "<M-L>", function()
      harpoon:list():replace_at(3)
    end, { desc = "Add to Harpoon list (index 3)" })
    vim.keymap.set("n", "<M-:>", function()
      harpoon:list():replace_at(4)
    end, { desc = "Add to Harpoon list (index 4)" })

    -- Toggle previous & next buffers stored within Harpoon list
    vim.keymap.set("n", "<M-P>", function()
      harpoon:list():prev()
    end)
    vim.keymap.set("n", "<M-N>", function()
      harpoon:list():next()
    end)
  end,
}
