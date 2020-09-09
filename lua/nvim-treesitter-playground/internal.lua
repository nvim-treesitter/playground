local configs = require 'nvim-treesitter.configs'
local ts_utils = require 'nvim-treesitter.ts_utils'
local printer = require 'nvim-treesitter-playground.printer'
local utils = require 'nvim-treesitter-playground.utils'
local ts_query = require 'nvim-treesitter.query'
local pl_query = require 'nvim-treesitter-playground.query'
local Promise = require 'nvim-treesitter-playground.promise'
local api = vim.api
local luv = vim.loop

local M = {}

local fs_mkdir = Promise.promisify(luv.fs_mkdir)
local fs_open = Promise.promisify(luv.fs_open)
local fs_write = Promise.promisify(luv.fs_write)
local fs_close = Promise.promisify(luv.fs_close)
local fs_stat = Promise.promisify(luv.fs_stat)
local fs_fstat = Promise.promisify(luv.fs_fstat)
local fs_read = Promise.promisify(luv.fs_read)

M._entries = setmetatable({}, {
  __index = function(tbl, key)
    local entry = rawget(tbl, key)

    if not entry then
      entry = {}
      rawset(tbl, key, entry)
    end

    return entry
  end
})

local playground_ns = api.nvim_create_namespace('nvim-treesitter-playground')
local query_hl_ns = api.nvim_create_namespace('nvim-treesitter-playground-query')

local function get_node_at_cursor()
  local success, node_at_point = pcall(function() return ts_utils.get_node_at_cursor() end)

  return success and node_at_point or nil
end

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
  local entry = M._entries[bufnr]

  close_buf(entry.display_bufnr)
  close_buf(entry.query_bufnr)
  M._entries[bufnr] = nil
end

local function is_buf_visible(bufnr)
  local windows = vim.fn.win_findbuf(bufnr)

  return #windows > 0
end

local function get_update_time()
  local config = configs.get_module 'playground'

  return config and config.updatetime or 25
end

local function setup_buf(for_buf)
  if M._entries[for_buf].display_bufnr then
    return M._entries[for_buf].display_bufnr
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
  api.nvim_buf_set_keymap(buf, 'n', 'i', string.format(':lua require "nvim-treesitter-playground.internal".toggle_highlights(%d)<CR>', for_buf), { silent = true })
  api.nvim_buf_set_keymap(buf, 'n', 'R', string.format(':lua require "nvim-treesitter-playground.internal".update(%d)<CR>', for_buf), { silent = true })
  api.nvim_buf_attach(buf, false, {
    on_detach = function() clear_entry(for_buf) end
  })

  return buf
end

local function setup_query_editor(bufnr)
  if M._entries[bufnr].query_bufnr then
    return M._entries[bufnr].query_bufnr
  end

  local buf = api.nvim_create_buf(false, false)

  api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  api.nvim_buf_set_option(buf, 'swapfile', false)
  api.nvim_buf_set_option(buf, 'buflisted', false)
  api.nvim_buf_set_option(buf, 'filetype', 'query')

  vim.cmd(string.format([[autocmd CursorMoved <buffer=%d> lua require'nvim-treesitter-playground.internal'.on_query_cursor_move(%d)]], buf, bufnr))

  api.nvim_buf_set_keymap(buf, 'n', 'R', string.format(':lua require "nvim-treesitter-playground.internal".update_query(%d, %d)<CR>', bufnr, buf), { silent = true })
  api.nvim_buf_attach(buf, false, {
    on_lines = utils.debounce(function() M.update_query(bufnr, buf) end, 1000)
  })

  local config = configs.get_module 'playground'

  if config.persist_queries then
    M.read_saved_query(bufnr):then_(vim.schedule_wrap(function(lines)
      if #lines > 0 then
        api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      end
    end))
  end

  return buf
end

local function get_cache_path()
  return vim.fn.stdpath('cache') .. '/nvim_treesitter_playground'
end

local function get_filename(bufnr)
  return vim.fn.fnamemodify(vim.fn.bufname(bufnr), ':t')
end

function M.save_query_file(bufnr, query)
  local cache_path = get_cache_path()
  local filename = get_filename(bufnr)

  fs_stat(cache_path)
    :catch(function() return fs_mkdir(cache_path, 493) end)
    :then_(function() return fs_open(cache_path .. '/' .. filename .. '~', 'w', 493) end)
    :then_(function(fd)
      return fs_write(fd, query, -1):then_(function() return fd end)
    end)
    :then_(function(fd) return fs_close(fd) end)
    :catch(function(err) print(err) end)
end

function M.read_saved_query(bufnr)
  local cache_path = get_cache_path()
  local filename = get_filename(bufnr)
  local query_path = cache_path .. '/' .. filename .. '~'

  return fs_open(query_path, 'r', 438)
    :then_(function(fd) return fs_fstat(fd)
      :then_(function(stat) return fs_read(fd, stat.size, 0) end)
      :then_(function(data) return fs_close(fd)
        :then_(function() return vim.split(data, '\n') end) end)
    end)
    :catch(function(err) return {} end)
end

function M.highlight_playground_nodes(bufnr, nodes)
  local entry = M._entries[bufnr]
  local results = entry.results
  local display_buf = entry.display_bufnr
  local lines = {}
  local count = 0

  if not results or not display_buf then return end

  for i, node in ipairs(results.nodes) do
    if vim.tbl_contains(nodes, node) then
      table.insert(lines, i)
      count = count + 1

      if count >= #nodes then
        break
      end
    end
  end

  for _, lnum in ipairs(lines) do
    local lines = api.nvim_buf_get_lines(display_buf, lnum - 1, lnum, false)

    if lines[1] then
      vim.api.nvim_buf_add_highlight(display_buf, playground_ns, 'TSPlaygroundFocus', lnum - 1, 0, -1)
    end
  end

  return lines
end

function M.highlight_playground_node_from_buffer(bufnr)
  M.clear_playground_highlights(bufnr)

  local display_buf = M._entries[bufnr].display_bufnr

  if not display_buf then return end

  local node_at_point = get_node_at_cursor()

  if not node_at_point then return end

  local lnums = M.highlight_playground_nodes(bufnr, { node_at_point })

  if lnums[1] then
    utils.for_each_buf_window(display_buf, function(window)
      api.nvim_win_set_cursor(window, { lnums[1], 0 })
    end)
  end
end

M._highlight_playground_node_debounced = utils.debounce(M.highlight_playground_node_from_buffer, get_update_time)

function M.highlight_node(bufnr)
  M.clear_highlights(bufnr)

  local row, _ = unpack(api.nvim_win_get_cursor(0))
  local results = M._entries[bufnr].results

  if not results then return end

  local node = results.nodes[row]

  if not node then return end

  local start_row, start_col, _ = node:start()

  M.highlight_nodes(bufnr, { node })

  utils.for_each_buf_window(bufnr, function(window)
    api.nvim_win_set_cursor(window, { start_row + 1, start_col })
  end)
end

function M.highlight_nodes(bufnr, nodes)
  for _, node in ipairs(nodes) do
    ts_utils.highlight_node(node, bufnr, playground_ns, 'TSPlaygroundFocus')
  end
end

function M.update_query(bufnr, query_bufnr)
  local query = table.concat(api.nvim_buf_get_lines(query_bufnr, 0, -1, false), '\n')
  local matches = pl_query.parse(bufnr, query)
  local capture_by_color = {}
  local index = 1

  local config = configs.get_module 'playground'

  if config.persist_queries then
    M.save_query_file(bufnr, query)
  end

  M._entries[bufnr].query_results = matches
  M._entries[bufnr].captures = {}
  M.clear_highlights(query_bufnr, query_hl_ns)
  M.clear_highlights(bufnr, query_hl_ns)

  for capture_match in ts_query.iter_group_results(query_bufnr, 'captures') do
    table.insert(M._entries[bufnr].captures, capture_match.capture)

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

function M.highlight_matched_query_nodes_from_capture(bufnr, capture)
  local query_results = M._entries[bufnr].query_results
  local display_buf = M._entries[bufnr].display_bufnr

  if not query_results then return end

  local nodes_to_highlight = {}

  for _, result in ipairs(query_results) do
    if result.tag == capture then
      table.insert(nodes_to_highlight, result.node)
    end
  end

  M.highlight_nodes(bufnr, nodes_to_highlight)

  if display_buf then
    M.highlight_playground_nodes(bufnr, nodes_to_highlight)
  end
end

function M.on_query_cursor_move(bufnr)
  local node_at_point = get_node_at_cursor()
  local captures = M._entries[bufnr].captures

  M.clear_highlights(bufnr)
  M.clear_highlights(M._entries[bufnr].display_bufnr)

  if not node_at_point or not captures then return end

  for _, capture in ipairs(captures) do
    local _, _, capture_start = capture.def.node:start()
    local _, _, capture_end = capture.def.node:end_()
    local _, _, start = node_at_point:start()
    local _, _, _end = node_at_point:end_()
    local capture_name = ts_utils.get_node_text(capture.name.node)[1]

    if start >= capture_start and _end <= capture_end and capture_name then
      M.highlight_matched_query_nodes_from_capture(bufnr, capture_name)
      break
    end
  end
end

function M.clear_highlights(bufnr, namespace)
  if not bufnr then return end

  local namespace = namespace or playground_ns

  api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
end

function M.clear_playground_highlights(bufnr)
  M.clear_highlights(M._entries[bufnr].display_bufnr)
end

function M.toggle_query_editor(bufnr)
  local bufnr = bufnr or api.nvim_get_current_buf()
  local display_buf = M._entries[bufnr].display_bufnr
  local current_win = api.nvim_get_current_win()

  if not display_buf then
    display_buf = M.open(bufnr)
  end

  local query_buf = setup_query_editor(bufnr)

  if is_buf_visible(query_buf) then
    close_buf_windows(query_buf)
  else
    M._entries[bufnr].query_bufnr = query_buf

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

  M._entries[bufnr].display_bufnr = display_buf
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
  local display_buf = M._entries[bufnr].display_bufnr

  if display_buf and is_buf_visible(display_buf) then
    close_buf_windows(M._entries[bufnr].query_bufnr)
    close_buf_windows(display_buf)
  else
    M.open(bufnr)
  end
end

local print_virt_hl = false

function M.toggle_highlights(bufnr)
  print_virt_hl = not print_virt_hl
  local bufnr = bufnr or api.nvim_get_current_buf()
  local display_buf = M._entries[bufnr].display_bufnr

  if print_virt_hl then
    printer.print_hl_groups(bufnr, display_buf)
  else
    printer.remove_hl_groups(display_buf)
  end
end

function M.update(bufnr)
  local bufnr = bufnr or api.nvim_get_current_buf()
  local display_buf = M._entries[bufnr].display_bufnr

  -- Don't bother updating if the playground isn't shown
  if not display_buf or not is_buf_visible(display_buf) then return end

  local results = printer.print(bufnr)

  M._entries[bufnr].results = results

  api.nvim_buf_set_lines(display_buf, 0, -1, false, results.lines)
  if print_virt_hl then
    printer.print_hl_groups(bufnr, display_buf)
  end
end

function M.attach(bufnr, lang)
  api.nvim_buf_attach(bufnr, true, {
    on_lines = vim.schedule_wrap(function() M.update(bufnr) end)
  })

  vim.cmd(string.format('augroup TreesitterPlayground_%d', bufnr))
  vim.cmd 'au!'
  vim.cmd(string.format([[autocmd CursorMoved <buffer=%d> lua require'nvim-treesitter-playground.internal'._highlight_playground_node_debounced(%d)]], bufnr, bufnr))
  vim.cmd(string.format([[autocmd BufLeave <buffer=%d> lua require'nvim-treesitter-playground.internal'.clear_playground_highlights(%d)]], bufnr, bufnr))
  vim.cmd 'augroup END'
end

function M.detach(bufnr)
  clear_entry(bufnr)
  vim.cmd(string.format('autocmd! TreesitterPlayground_%d CursorMoved', bufnr))
  vim.cmd(string.format('autocmd! TreesitterPlayground_%d BufLeave', bufnr))
end

return M
