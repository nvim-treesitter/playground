local configs = require 'nvim-treesitter.configs'
local ts_utils = require 'nvim-treesitter.ts_utils'
local printer = require 'nvim-treesitter-playground.printer'
local utils = require 'nvim-treesitter-playground.utils'
local ts_query = require 'nvim-treesitter.query'
local pl_query = require 'nvim-treesitter-playground.query'
local api = vim.api

local M = {}

M._displays_by_buf = {}
M._results_by_buf = {}
M._queries_by_buf = {}

local playground_ns = api.nvim_create_namespace('nvim-treesitter-playground')
local query_hl_ns = api.nvim_create_namespace('nvim-treesitter-playground-query')

local function focus_buf(bufnr)
  if not bufnr then return end

  local windows = vim.fn.win_findbuf(bufnr)

  if windows[1] then
    api.nvim_set_current_win(windows[1])
  end
end

local function close_buf_windows(bufnr)
  if not bufnr then return end

  utils.for_each_buf_window(bufnr, function(window)
    api.nvim_win_close(window, true)
  end)
end

local function close_buf(bufnr)
  if not bufnr then return end

  close_buf_windows(bufnr)

  if api.nvim_buf_is_loaded(bufnr) then
    vim.cmd(string.format("bw! %d", bufnr))
  end
end

local function clear_entry(bufnr)
  local display_buf = M._displays_by_buf[bufnr]
  local query_buf = M._queries_by_buf[bufnr]

  close_buf(display_buf)
  close_buf(query_buf)
  M._displays_by_buf[bufnr] = nil
  M._results_by_buf[bufnr] = nil
  M._queries_by_buf[bufnr] = nil
end

local function is_buf_visible(bufnr)
  local windows = vim.fn.win_findbuf(bufnr)

  return #windows > 0
end

local function setup_buf(for_buf)
  if M._displays_by_buf[for_buf] then
    return M._displays_by_buf[for_buf]
  end

  local buf = api.nvim_create_buf(false, false)

  api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  api.nvim_buf_set_option(buf, 'swapfile', false)
  api.nvim_buf_set_option(buf, 'buflisted', false)
  api.nvim_buf_set_option(buf, 'filetype', 'tsplayground')

  vim.cmd(string.format('augroup TreesitterPlayground_%d', buf))
  vim.cmd 'au!'
  vim.cmd(string.format([[autocmd CursorMoved <buffer=%d> lua require'nvim-treesitter-playground.internal'.highlight_node(%d)]], buf, for_buf))
  vim.cmd(string.format([[autocmd BufLeave <buffer=%d> lua require'nvim-treesitter-playground.internal'.clear_highlights(%d)]], buf, for_buf))
  vim.cmd(string.format([[autocmd BufWinEnter <buffer=%d> lua require'nvim-treesitter-playground.internal'.update(%d)]], buf, for_buf))
  vim.cmd 'augroup END'

  api.nvim_buf_set_keymap(buf, 'n', 'o', string.format(':lua require "nvim-treesitter-playground.internal".toggle_query_editor(%d)<CR>', for_buf), { silent = true })
  api.nvim_buf_set_keymap(buf, 'n', 'R', string.format(':lua require "nvim-treesitter-playground.internal".update(%d)<CR>', for_buf), { silent = true })
  api.nvim_buf_attach(buf, false, {
    on_detach = function() clear_entry(for_buf) end
  })

  return buf
end

local function setup_query_editor(bufnr)
  if M._queries_by_buf[bufnr] then
    return M._queries_by_buf[bufnr]
  end

  local buf = api.nvim_create_buf(false, false)

  api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  api.nvim_buf_set_option(buf, 'swapfile', false)
  api.nvim_buf_set_option(buf, 'buflisted', false)
  api.nvim_buf_set_option(buf, 'filetype', 'query')

  M._queries_by_buf[bufnr] = buf

  api.nvim_buf_set_keymap(buf, 'n', 'R', string.format(':lua require "nvim-treesitter-playground.internal".update_query(%d, %d)<CR>', bufnr, buf), { silent = true })
  api.nvim_buf_attach(buf, false, {
    on_lines = utils.debounce(function() M.update_query(bufnr, buf) end, 1000)
  })

  return buf
end

M.highlight_playground_node = utils.debounce(function(bufnr)
  M.clear_playground_highlights(bufnr)

  local display_buf = M._displays_by_buf[bufnr]
  local results = M._results_by_buf[bufnr]

  if not display_buf or not results then return end

  local success, node_at_point = pcall(function() return ts_utils.get_node_at_cursor() end)

  if not success or not node_at_point then return end

  local line

  for i, node in ipairs(results.nodes) do
    if node_at_point == node then
      line = i - 1
      break
    end
  end

  if line then
    local lines = api.nvim_buf_get_lines(display_buf, line, line + 1, false)

    if lines[1] then
      vim.highlight.range(display_buf, playground_ns, 'TSPlaygroundFocus', { line, 0 }, { line, #lines[1] })
    end

    utils.for_each_buf_window(display_buf, function(window)
      api.nvim_win_set_cursor(window, { line + 1, 0 })
    end)
  end
end, function(bufnr)
  local config = configs.get_module 'playground'

  return config and config.updatetime or 25
end)

function M.highlight_node(bufnr)
  M.clear_highlights(bufnr)

  local row, _ = unpack(api.nvim_win_get_cursor(0))
  local results = M._results_by_buf[bufnr]

  if not results then return end

  local node = results.nodes[row]

  if not node then return end

  local start_row, start_col, _ = node:start()

  ts_utils.highlight_node(node, bufnr, playground_ns, 'TSPlaygroundFocus')

  utils.for_each_buf_window(bufnr, function(window)
    api.nvim_win_set_cursor(window, { start_row + 1, start_col })
  end)
end

function M.update_query(bufnr, query_bufnr)
  local query = table.concat(api.nvim_buf_get_lines(query_bufnr, 0, -1, false), '\n')
  local matches = pl_query.parse(bufnr, query)
  local capture_by_color = {}
  local index = 1

  M.clear_highlights(query_bufnr, query_hl_ns)
  M.clear_highlights(bufnr, query_hl_ns)

  print(bufnr, query_bufnr)

  for capture_match in ts_query.iter_group_results(query_bufnr, 'captures') do
    local capture = ts_utils.get_node_text(capture_match.capture.name.node)[1]

    if not capture_by_color[capture] then
      capture_by_color[capture] = 'TSPlaygroundCapture' .. index
      index = index + 1
    end

    ts_utils.highlight_node(capture_match.capture.def.node, query_bufnr, query_hl_ns, capture_by_color[capture])
  end

  local node_highlights = {}

  for _, match in ipairs(matches) do
    local hl_group = capture_by_color[match.tag]

    if hl_group then
      table.insert(node_highlights, { match.node, hl_group })
    end
  end

  for _, entry in ipairs(node_highlights) do
    ts_utils.highlight_node(entry[1], bufnr, query_hl_ns, entry[2])
  end
end

function M.clear_highlights(bufnr, namespace)
  local namespace = namespace or playground_ns

  api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
end

function M.clear_playground_highlights(bufnr)
  local display_buf = M._displays_by_buf[bufnr]

  if display_buf then
    M.clear_highlights(display_buf)
  end
end

function M.toggle_query_editor(bufnr)
  local bufnr = bufnr or api.nvim_get_current_buf()
  local display_buf = M._displays_by_buf[bufnr]
  local current_win = api.nvim_get_current_win()

  if not display_buf then
    display_buf = M.open(bufnr)
  end

  local query_buf = setup_query_editor(bufnr)

  if is_buf_visible(query_buf) then
    close_buf_windows(query_buf)
  else
    M._queries_by_buf[bufnr] = query_buf

    focus_buf(display_buf)
    vim.cmd "split"
    vim.cmd(string.format("buffer %d", query_buf))

    api.nvim_win_set_option(0, 'spell', false)
    api.nvim_win_set_option(0, 'number', true)

    api.nvim_set_current_win(current_win)
  end
end

function M.open(bufnr)
  local bufnr = bufnr or api.nvim_get_current_buf()
  local display_buf = setup_buf(bufnr)
  local current_window = api.nvim_get_current_win()

  M._displays_by_buf[bufnr] = display_buf
  vim.cmd "vsplit"
  vim.cmd(string.format("buffer %d", display_buf))

  api.nvim_win_set_option(0, 'spell', false)
  api.nvim_win_set_option(0, 'number', false)
  api.nvim_win_set_option(0, 'relativenumber', false)
  api.nvim_win_set_option(0, 'cursorline', false)

  api.nvim_set_current_win(current_window)

  return display_buf
end

function M.toggle(bufnr)
  local bufnr = bufnr or api.nvim_get_current_buf()
  local display_buf = M._displays_by_buf[bufnr]

  if display_buf and is_buf_visible(display_buf) then
    close_buf_windows(M._queries_by_buf[display_buf])
    close_buf_windows(display_buf)
  else
    M.open(bufnr)
  end
end

function M.update(bufnr)
  local bufnr = bufnr or api.nvim_get_current_buf()
  local display_buf = M._displays_by_buf[bufnr]

  -- Don't bother updating if the playground isn't shown
  if not display_buf or not is_buf_visible(display_buf) then return end

  local results = printer.print(bufnr)

  M._results_by_buf[bufnr] = results

  api.nvim_buf_set_lines(display_buf, 0, -1, false, results.lines)
end

function M.attach(bufnr, lang)
  local bufnr = bufnr or api.nvim_get_current_buf()
  local config = configs.get_module 'playground'

  api.nvim_buf_attach(bufnr, true, {
    on_lines = vim.schedule_wrap(function() M.update(bufnr) end)
    -- on_detach = function() clear_entry(bufnr) end
  })

  vim.cmd(string.format('augroup TreesitterPlayground_%d', bufnr))
  vim.cmd 'au!'
  vim.cmd(string.format([[autocmd CursorMoved <buffer=%d> lua require'nvim-treesitter-playground.internal'.highlight_playground_node(%d)]], bufnr, bufnr))
  vim.cmd(string.format([[autocmd BufLeave <buffer=%d> lua require'nvim-treesitter-playground.internal'.clear_playground_highlights(%d)]], bufnr, bufnr))
  vim.cmd 'augroup END'
end

function M.detach(bufnr)
  local config = configs.get_module 'playground'

  clear_entry(bufnr)
  vim.cmd(string.format('autocmd! TreesitterPlayground_%d CursorMoved', bufnr))
  vim.cmd(string.format('autocmd! TreesitterPlayground_%d BufLeave', bufnr))
end

return M
