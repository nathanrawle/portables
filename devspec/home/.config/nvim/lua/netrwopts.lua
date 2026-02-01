local utils = require("utils")
local extend_hide = {}
for _, s in ipairs(vim.g.never_show) do
  extend_hide[#extend_hide + 1] = "^" .. utils.escape_regex_specials(s) .. "$"
end

vim.g.loaded_netrw = nil
vim.g.loaded_netrwPlugin = nil
vim.g.netrw_altfile = 1 -- C-^ iuugnores netrw
vim.g.netrw_winsize = 32 -- explorer width/height when it does split
vim.g.netrw_list_hide = table.concat(
  vim.list_extend({
    "^\\./$",
    "^\\.\\./$",
  }, extend_hide),
  ","
)
