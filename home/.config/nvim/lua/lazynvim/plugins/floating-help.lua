return {
  "Tyler-Barham/floating-help.nvim",
  config = function()
    local fh = require("floating-help")

    fh.setup({
      -- Defaults
      width = 0.5, -- Whole numbers are columns/rows
      height = 0.9, -- Decimals are a percentage of the editor
      position = "NE", -- NW,N,NE,W,C,E,SW,S,SE (C==center)
      border = "rounded", -- rounded,double,single
      onload = function(query_type)
        local buf = vim.api.nvim_get_current_buf()
        local win = vim.api.nvim_get_current_win()
        vim.wo[win].winbar = "%#Title#" .. query_type .. "%=%t%="
        vim.keymap.set("n", "q", fh.toggle, { buffer = buf, desc = "Hide floating-help" })
        vim.keymap.set({ "n", "i" }, "<esc>", fh.toggle, { buffer = buf, desc = "Hide floating-help" })
      end,
    })

    vim.keymap.set("n", "<leader>h", fh.toggle)
    vim.keymap.set("n", "fwh", function()
      fh.open("t=help", vim.fn.expand("<cword>"))
    end, { desc = "Find word under cursor in help pages" })
    vim.keymap.set("n", "fwm", function()
      fh.open("t=man", vim.fn.expand("<cword>"))
    end, { desc = "Find word under cursor in man pages" })

    -- Only replace cmds, not search; only replace the first instance
    local function cmd_abbrev(abbrev, expansion)
      local cmd = "cabbr "
        .. abbrev
        .. ' <c-r>=(getcmdpos() == 1 && getcmdtype() == ":" ? "'
        .. expansion
        .. '" : "'
        .. abbrev
        .. '")<CR>'
      vim.cmd(cmd)
    end

    -- Redirect `:h` to `:FloatingHelp`
    cmd_abbrev("h", "FloatingHelp")
    cmd_abbrev("help", "FloatingHelp")
    cmd_abbrev("helpc", "FloatingHelpClose")
    cmd_abbrev("helpclose", "FloatingHelpClose")
  end,
}
