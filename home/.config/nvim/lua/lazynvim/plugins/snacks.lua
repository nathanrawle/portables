return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    lazygit = { enabled = true },
    image = {
      enabled = true,
      doc = {
        enabled = true,
        inline = true,
        float = true,
      },
    },
  },
  config = function(_, opts)
    -- Workaround for snacks#2332: under tmux + extended-keys, nvim's
    -- TermResponse autocmd doesn't fire, so Snacks' escape-sequence
    -- terminal detection (`\e[>q`) leaks its response into the active
    -- buffer. With netrw open at startup, the `o` in "ghostty" gets
    -- interpreted as Hexplore and splits the netrw window.
    --
    -- Snacks has its own workaround that queries tmux directly via
    -- `tmux display-message -p '#{client_termname}'`, but it only
    -- activates when `extended-keys` is set to "on" — not "always".
    -- We replicate that workaround here and pre-populate Snacks'
    -- terminal cache before snacks.setup() runs, so detection is
    -- short-circuited and the escape sequence is never sent.
    pcall(function()
      if not vim.env.TMUX then
        return
      end
      local terminal = require("snacks.image.terminal")
      if terminal._terminal then
        return
      end
      local out = vim.fn.system({ "tmux", "display-message", "-p", "#{client_termname}" })
      if vim.v.shell_error ~= 0 then
        return
      end
      terminal._terminal = {
        terminal = vim.trim(out):gsub("^xterm%-", ""),
        version = "unknown",
      }
      -- Replicate the tmux setup that Snacks' detect() does: enable
      -- per-pane passthrough and install the DCS-wrapping transform so
      -- graphics escape sequences reach the underlying terminal. Without
      -- the transform, Snacks writes raw Kitty graphics commands and tmux
      -- silently drops them.
      pcall(vim.fn.system, { "tmux", "set", "-p", "allow-passthrough", "all" })
      terminal.transform = function(data)
        return ("\027Ptmux;" .. data:gsub("\027", "\027\027")) .. "\027\\"
      end
    end)
    require("snacks").setup(opts)
  end,
  keys = {
    {
      "<leader>gg",
      function()
        Snacks.lazygit()
      end,
      desc = "LazyGit",
    },
  },
}
