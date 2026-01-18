vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")
vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostic qf list" })
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })
vim.keymap.set("n", "\\", "<cmd>Rexplore<cr>", { desc = "Toggle explorer" })

-- Move selection
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

-- Make navigation easier on the eyes
vim.keymap.set("n", "J", "mzJ`z")
-- vim.keymap.set("n", "<C-d>", "<C-d>zz")
-- vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")
vim.keymap.set("n", "=ap", "ma=ap'a")

vim.keymap.set("n", "<C-k>", "<cmd>cnext<CR>zz") -- next error in qf list
vim.keymap.set("n", "<C-j>", "<cmd>cprev<CR>zz") -- previous error in qf list
vim.keymap.set("n", "<leader>k", "<cmd>lnext<CR>zz") -- next error in location list
vim.keymap.set("n", "<leader>j", "<cmd>lprev<CR>zz") -- previous error in location list

-- Editor conveniences
vim.keymap.set("x", "<leader>p", [["_dP]]) -- Paste over selection to void
vim.keymap.set({ "n", "v" }, "<leader>d", [["_d]]) -- delete to void
vim.keymap.set("n", "<M-C-L>", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]])
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })
