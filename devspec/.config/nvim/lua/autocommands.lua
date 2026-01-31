-- Highlight when yanking (copying) text
vim.api.nvim_create_autocmd("TextYankPost", {
  desc = "Highlight when yanking (copying) text",
  group = vim.api.nvim_create_augroup("kickstart-highlight-yank", { clear = true }),
  callback = function()
    vim.hl.on_yank()
  end,
})

-- Open netrw when starting `nvim` with no file args (i.e. `nvim`), in the current cwd.
-- Does NOT interfere with: `nvim file`, `nvim dir`, piped stdin, dashboards, special buffers, etc.
vim.api.nvim_create_autocmd("VimEnter", {
  desc = "Open NetRW by default when nvim is called without arguments",
  group = vim.api.nvim_create_augroup("my-autocommands", { clear = true }),
  callback = function()
    -- Don't interfere if files/args were provided.
    if vim.fn.argc() ~= 0 then
      return
    end

    -- Don't interfere with piped input / `nvim -` style use.
    -- When stdin has content, the current buffer won't be "empty".
    if vim.fn.line2byte("$") ~= -1 then
      return
    end

    local buf = vim.api.nvim_get_current_buf()

    -- Only act on a normal, unnamed, unmodified empty buffer.
    if vim.bo[buf].buftype ~= "" then
      return
    end
    if vim.api.nvim_buf_get_name(buf) ~= "" then
      return
    end
    if vim.bo[buf].modified then
      return
    end
    if vim.api.nvim_buf_line_count(buf) ~= 1 then
      return
    end
    if vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] ~= "" then
      return
    end

    -- Optional: if you use dashboards, this prevents fighting them in edge cases
    -- where they didn't set buftype but did set filetype.
    if vim.bo[buf].filetype ~= "" then
      return
    end

    vim.cmd("silent! Explore")
  end,
})
