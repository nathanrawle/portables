-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- vimeogen keymaps
vim.keymap.set("n", "J", "mzJ`z", { desc = "Join Lines" })
vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Half Window Down" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Half Window Up" })
vim.keymap.set("n", "n", "nzzzv", { desc = "Repeat Prev Search" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Repeat Prev Search Backwards" })
vim.keymap.set("n", "=ap", "ma=ap'a", { desc = "Fix Block Indent" })

-- greatest remap ever
vim.keymap.set("x", "<leader>p", [["_dP]], { desc = "Void and Paste" })
vim.keymap.set({ "n", "v" }, "<leader>vd", '"_d', { desc = "Delete to Void Buffer" })

vim.keymap.set(
  "n",
  "<Esc><C-l>",
  [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]],
  { desc = "Global Replace Word" }
)
vim.keymap.set("n", "<leader>X", "<cmd>!chmod +x %<CR>", { silent = true, desc = "Make current file executable" })
