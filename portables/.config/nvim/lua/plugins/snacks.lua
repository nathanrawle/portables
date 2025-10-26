-- ~/.config/nvim/lua/plugins/snacks.lua
return {
  {
    "folke/snacks.nvim",
    opts = {
      -- Explorer pane (opened with <leader>e in LazyVim)
      explorer = {
        hidden = true, -- show dotfiles
        ignored = true, -- also show .gitignore'd files (optional)
        preview = true,
      },

      -- If you also want pickers (find files, grep) to include hidden/ignored:
      picker = {
        hidden = true,
        ignored = true,
        -- some people also set it on the files source, but the top-level flags matter
        sources = { files = { hidden = true, ignored = true } },
      },
    },
  },
}
