return {
  "MeanderingProgrammer/render-markdown.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "folke/snacks.nvim",
  },
  ft = { "markdown" },
  config = function()
    -- Snacks queries the terminal with a Kitty graphics escape sequence and
    -- caches the result. If the terminal supports it (including tmux with
    -- passthrough enabled), Snacks renders LaTeX as rasterized images and we
    -- disable render-markdown's Unicode-based LaTeX renderer to avoid double
    -- rendering. Otherwise, render-markdown handles LaTeX as Unicode.
    --
    -- Deferred via vim.schedule so Snacks' UIEnter pre-warm always completes
    -- first — otherwise launching `nvim file.md` can trigger detection here
    -- with a cold cache, leaking the terminal response into the buffer.
    vim.schedule(function()
      local kitty_graphics = require("snacks.image").supports_terminal()
      require("render-markdown").setup({
        latex = { enabled = not kitty_graphics },
        code = {
          -- Snacks renders mermaid blocks as inline images by injecting
          -- Unicode placeholder characters into the code block. If
          -- render-markdown conceals the block, those placeholders get
          -- hidden and the image only flickers in when the cursor lands
          -- on the unconcealed line. Skip rendering for mermaid so Snacks
          -- owns the whole block.
          disable = { "mermaid" },
        },
      })
    end)
  end,
}
