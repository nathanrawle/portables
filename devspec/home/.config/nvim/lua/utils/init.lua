local M = {}

function M.repeat_flag_with_args(flag, args)
  local out = {}
  for _, v in ipairs(args) do
    out[#out + 1] = flag
    out[#out + 1] = v
  end
  return out
end

function M.escape_regex_literals(str)
  return vim.fn.escape(str, [[+?(){}|]])
end

function M.escape_regex_specials(str)
  return vim.fn.escape(str, [[\.^$[]*]])
end

return M
