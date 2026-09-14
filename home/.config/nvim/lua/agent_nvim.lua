local M = {}

local socket_option = "@taw_nvim_socket"
local pid_option = "@taw_nvim_pid"
local registrations_option = "@taw_nvim_registrations"
local highlight_namespace = vim.api.nvim_create_namespace("taw-agent-nvim")
local selection_limit = 64 * 1024
local diagnostic_limit = 200

local function tmux(args)
  if vim.env.TMUX == nil or vim.env.TMUX_PANE == nil or vim.fn.executable("tmux") ~= 1 then
    return nil
  end

  local command = { "tmux" }
  vim.list_extend(command, args)
  local output = vim.fn.system(command)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return vim.trim(output)
end

local function server_address()
  local address = vim.v.servername
  if address == "" then
    local ok, result = pcall(vim.fn.serverstart)
    if not ok then
      return nil
    end
    address = result
  end

  -- Local named pipes avoid adding a network listener for agent access.
  if type(address) ~= "string" or address:sub(1, 1) ~= "/" then
    return nil
  end
  return address
end

local function read_registrations(pane)
  local encoded = tmux({ "show-option", "-pqv", "-t", pane, registrations_option })
  if encoded == nil or encoded == "" then
    return {}
  end

  local ok, decoded = pcall(vim.json.decode, encoded)
  if not ok or type(decoded) ~= "table" then
    return {}
  end

  local registrations = {}
  for _, registration in ipairs(decoded) do
    if type(registration) == "table"
      and type(registration.pid) == "string"
      and registration.pid:match("^%d+$")
      and type(registration.socket) == "string"
      and registration.socket:sub(1, 1) == "/" then
      table.insert(registrations, registration)
    end
  end
  return registrations
end

local function write_registrations(pane, registrations)
  if #registrations == 0 then
    tmux({ "set-option", "-pu", "-t", pane, registrations_option })
    tmux({ "set-option", "-pu", "-t", pane, socket_option })
    tmux({ "set-option", "-pu", "-t", pane, pid_option })
    return
  end

  local current = registrations[#registrations]
  tmux({ "set-option", "-p", "-t", pane, registrations_option, vim.json.encode(registrations) })
  tmux({ "set-option", "-p", "-t", pane, pid_option, current.pid })
  tmux({ "set-option", "-p", "-t", pane, socket_option, current.socket })
end

local function publish()
  local pane = vim.env.TMUX_PANE
  local address = server_address()
  if pane == nil or address == nil then
    return
  end

  local pid = tostring(vim.fn.getpid())
  local registrations = read_registrations(pane)
  if #registrations == 0 then
    local existing_socket = tmux({ "show-option", "-pqv", "-t", pane, socket_option })
    local existing_pid = tmux({ "show-option", "-pqv", "-t", pane, pid_option })
    local has_existing = existing_socket ~= nil and existing_socket ~= ""
      and existing_pid ~= nil and existing_pid ~= ""
    if has_existing then
      table.insert(registrations, { pid = existing_pid, socket = existing_socket })
    end
  end

  local updated = {}
  for _, registration in ipairs(registrations) do
    if registration.pid ~= pid and registration.socket ~= address then
      table.insert(updated, registration)
    end
  end
  table.insert(updated, { pid = pid, socket = address })
  write_registrations(pane, updated)

  vim.api.nvim_create_autocmd("VimLeavePre", {
    desc = "Remove this Neovim instance's tmux registration",
    group = vim.api.nvim_create_augroup("taw-agent-nvim", { clear = true }),
    callback = function()
      local remaining = {}
      for _, registration in ipairs(read_registrations(pane)) do
        if registration.pid ~= pid and registration.socket ~= address then
          table.insert(remaining, registration)
        end
      end
      write_registrations(pane, remaining)
    end,
  })
end

local function visual_selection(mode)
  local visual_mode = mode:sub(1, 1)
  if visual_mode ~= "v" and visual_mode ~= "V" and visual_mode ~= "\22" then
    return nil
  end

  local anchor = vim.fn.getpos("v")
  local cursor = vim.fn.getpos(".")
  local ok, region = pcall(vim.fn.getregion, anchor, cursor, { type = visual_mode })
  if not ok then
    return nil
  end

  local text = table.concat(region, "\n")
  local limited = vim.fn.strpart(text, 0, selection_limit, true)
  if #limited > selection_limit then
    limited = vim.fn.strcharpart(limited, 0, vim.fn.strchars(limited) - 1)
  end
  return {
    mode = visual_mode,
    anchor = { line = anchor[2], column = anchor[3] },
    cursor = { line = cursor[2], column = cursor[3] },
    text = limited,
    truncated = #limited < #text,
  }
end

local function diagnostics(buffer)
  local result = {}
  local all = vim.diagnostic.get(buffer)
  for index = 1, math.min(#all, diagnostic_limit) do
    local diagnostic = all[index]
    table.insert(result, {
      line = diagnostic.lnum + 1,
      column = diagnostic.col + 1,
      end_line = (diagnostic.end_lnum or diagnostic.lnum) + 1,
      end_column = (diagnostic.end_col or diagnostic.col) + 1,
      severity = vim.diagnostic.severity[diagnostic.severity],
      source = diagnostic.source,
      code = diagnostic.code,
      message = diagnostic.message,
    })
  end
  return result, #all > diagnostic_limit
end

function M.context()
  local buffer = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local mode = vim.fn.mode(1)
  local current_diagnostics, diagnostics_truncated = diagnostics(buffer)

  return {
    pid = vim.fn.getpid(),
    cwd = vim.fn.getcwd(),
    file = vim.api.nvim_buf_get_name(buffer),
    buffer = buffer,
    filetype = vim.bo[buffer].filetype,
    modified = vim.bo[buffer].modified,
    cursor = { line = cursor[1], column = cursor[2] + 1 },
    mode = mode,
    selection = visual_selection(mode),
    diagnostics = current_diagnostics,
    diagnostics_truncated = diagnostics_truncated,
  }
end

local function decode_hex(value)
  if type(value) ~= "string" or value:find("[^0-9a-f]") or #value % 2 ~= 0 then
    error("invalid hex path")
  end

  return (value:gsub("..", function(pair)
    return string.char(tonumber(pair, 16))
  end))
end

local function load_buffer(path_hex)
  local path = decode_hex(path_hex)
  local buffer = vim.fn.bufadd(path)
  vim.fn.bufload(buffer)
  return buffer
end

local function focus_buffer(buffer, line, column)
  vim.api.nvim_set_current_buf(buffer)

  local last_line = vim.api.nvim_buf_line_count(buffer)
  line = math.max(1, math.min(tonumber(line) or 1, last_line))
  local text = vim.api.nvim_buf_get_lines(buffer, line - 1, line, false)[1] or ""
  column = math.max(1, math.min(tonumber(column) or 1, #text + 1))
  vim.api.nvim_win_set_cursor(0, { line, column - 1 })
  vim.cmd("normal! zv")
  return buffer
end

function M.open(path_hex, line, column)
  focus_buffer(load_buffer(path_hex), line, column)
  return M.context()
end

function M.highlight(path_hex, ranges)
  local buffer = load_buffer(path_hex)
  local last_line = vim.api.nvim_buf_line_count(buffer)
  local first_line
  local validated_ranges = {}

  for range in ranges:gmatch("[^,]+") do
    local start_line, end_line = range:match("^(%d+):(%d+)$")
    start_line = tonumber(start_line)
    end_line = tonumber(end_line)
    if start_line == nil or end_line == nil or start_line > end_line or end_line > last_line then
      error("highlight range is outside the buffer")
    end
    first_line = first_line or start_line
    table.insert(validated_ranges, { start_line, end_line })
  end

  vim.api.nvim_buf_clear_namespace(buffer, highlight_namespace, 0, -1)
  for _, range in ipairs(validated_ranges) do
    local start_line = range[1]
    local end_line = range[2]
    vim.api.nvim_buf_set_extmark(buffer, highlight_namespace, start_line - 1, 0, {
      end_row = end_line,
      end_col = 0,
      hl_group = "Visual",
      hl_eol = true,
    })
  end

  if first_line ~= nil then
    focus_buffer(buffer, first_line, 1)
  end
  return M.context()
end

function M.clear_highlights(path_hex)
  if path_hex ~= "" then
    local path = decode_hex(path_hex)
    local buffer = vim.fn.bufnr(path)
    if buffer >= 0 then
      vim.api.nvim_buf_clear_namespace(buffer, highlight_namespace, 0, -1)
    end
    return true
  end

  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buffer) then
      vim.api.nvim_buf_clear_namespace(buffer, highlight_namespace, 0, -1)
    end
  end
  return true
end

function M.clear_current_highlights()
  vim.api.nvim_buf_clear_namespace(0, highlight_namespace, 0, -1)
end

function M.setup()
  publish()
end

return M
