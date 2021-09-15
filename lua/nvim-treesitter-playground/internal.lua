local parsers = require "nvim-treesitter.parsers"
local configs = require "nvim-treesitter.configs"
local ts_utils = require "nvim-treesitter.ts_utils"
local printer = require "nvim-treesitter-playground.printer"
local utils = require "nvim-treesitter-playground.utils"
local ts_query = require "nvim-treesitter.query"
local pl_query = require "nvim-treesitter-playground.query"
local Promise = require "nvim-treesitter-playground.promise"
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
      entry = {
        include_anonymous_nodes = false,
        suppress_injected_languages = false,
        include_language = false,
        include_hl_groups = false,
        focused_language_tree = nil,
      }
      rawset(tbl, key, entry)
    end

    return entry
  end,
})

local query_buf_var_name = "TSPlaygroundForBuf"
local playground_ns = api.nvim_create_namespace "nvim-treesitter-playground"
local query_hl_ns = api.nvim_create_namespace "nvim-treesitter-playground-query"

local function get_node_at_cursor(options)
  options = options or {}

  local include_anonymous = options.include_anonymous
  local lnum, col = unpack(vim.api.nvim_win_get_cursor(0))
  local root_lang_tree = parsers.get_parser()

  -- This can happen in some scenarios... best not assume.
  if not root_lang_tree then
    return
  end

  local owning_lang_tree = root_lang_tree:language_for_range { lnum - 1, col, lnum - 1, col }
  local result

  for _, tree in ipairs(owning_lang_tree:trees()) do
    local range = { lnum - 1, col, lnum - 1, col }

    if utils.node_contains(tree:root(), range) then
      if include_anonymous then
        result = tree:root():descendant_for_range(unpack(range))
      else
        result = tree:root():named_descendant_for_range(unpack(range))
      end

      if result then
        return result
      end
    end
  end
end

local function focus_buf(bufnr)
  if not bufnr then
    return
  end

  local windows = vim.fn.win_findbuf(bufnr)

  if windows[1] then
    api.nvim_set_current_win(windows[1])
  end
end

local function close_buf_windows(bufnr)
  if not bufnr then
    return
  end

  utils.for_each_buf_window(bufnr, function(window)
    api.nvim_win_close(window, true)
  end)
end

local function close_buf(bufnr)
  if not bufnr then
    return
  end

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
  local config = configs.get_module "playground"

  return config and config.updatetime or 25
end

local function make_entry_toggle(property, options)
  options = options or {}

  local update_fn = options.update_fn or function(entry)
    entry[property] = not entry[property]
  end

  return function(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    update_fn(M._entries[bufnr])

    local current_cursor = vim.api.nvim_win_get_cursor(0)
    local node_at_cursor = M.get_current_node(bufnr)

    if options.reprocess then
      M.update(bufnr)
    else
      M.render(bufnr)
    end

    -- Restore the cursor to the same node or at least the previous cursor position.
    local cursor_pos = current_cursor
    local node_entries = M._entries[bufnr].results

    if node_at_cursor then
      for lnum, node_entry in ipairs(node_entries) do
        if node_entry.node:id() == node_at_cursor:id() then
          cursor_pos = { lnum, cursor_pos[2] }
        end
      end
    end

    -- This could be out of bounds
    -- TODO(steelsojka): set to end if out of bounds
    pcall(vim.api.nvim_win_set_cursor, 0, cursor_pos)
  end
end

local function setup_buf(for_buf)
  if M._entries[for_buf].display_bufnr then
    return M._entries[for_buf].display_bufnr
  end

  local buf = api.nvim_create_buf(false, false)

  api.nvim_buf_set_option(buf, "buftype", "nofile")
  api.nvim_buf_set_option(buf, "swapfile", false)
  api.nvim_buf_set_option(buf, "buflisted", false)
  api.nvim_buf_set_option(buf, "filetype", "tsplayground")
  api.nvim_buf_set_var(buf, query_buf_var_name, for_buf)

  vim.cmd(string.format("augroup TreesitterPlayground_%d", buf))
  vim.cmd "au!"
  vim.cmd(
    string.format(
      [[autocmd CursorMoved <buffer=%d> lua require'nvim-treesitter-playground.internal'.highlight_node(%d)]],
      buf,
      for_buf
    )
  )
  vim.cmd(
    string.format(
      [[autocmd BufLeave <buffer=%d> lua require'nvim-treesitter-playground.internal'.clear_highlights(%d)]],
      buf,
      for_buf
    )
  )
  vim.cmd(
    string.format(
      [[autocmd BufWinEnter <buffer=%d> lua require'nvim-treesitter-playground.internal'.update(%d)]],
      buf,
      for_buf
    )
  )
  vim.cmd "augroup END"

  local config = configs.get_module "playground"

  for func, mapping in pairs(config.keybindings) do
    api.nvim_buf_set_keymap(
      buf,
      "n",
      mapping,
      string.format(':lua require "nvim-treesitter-playground.internal".%s(%d)<CR>', func, for_buf),
      { silent = true, noremap = true }
    )
  end
  api.nvim_buf_attach(buf, false, {
    on_detach = function()
      clear_entry(for_buf)
    end,
  })

  return buf
end

local function resolve_lang_tree(bufnr)
  local entry = M._entries[bufnr]

  if entry.focused_language_tree then
    local root_lang_tree = parsers.get_parser(bufnr)
    local found

    root_lang_tree:for_each_child(function(lang_tree)
      if not found and lang_tree == entry.focused_language_tree then
        found = lang_tree
      end
    end)

    if found then
      return found
    end
  end
end

local function setup_query_editor(bufnr)
  if M._entries[bufnr].query_bufnr then
    return M._entries[bufnr].query_bufnr
  end

  local buf = api.nvim_create_buf(false, false)

  api.nvim_buf_set_option(buf, "buftype", "nofile")
  api.nvim_buf_set_option(buf, "swapfile", false)
  api.nvim_buf_set_option(buf, "buflisted", false)
  api.nvim_buf_set_option(buf, "filetype", "query")
  api.nvim_buf_set_var(buf, query_buf_var_name, bufnr)

  vim.cmd(
    string.format(
      [[autocmd CursorMoved <buffer=%d> lua require'nvim-treesitter-playground.internal'.on_query_cursor_move(%d)]],
      buf,
      bufnr
    )
  )

  api.nvim_buf_set_keymap(
    buf,
    "n",
    "R",
    string.format(':lua require "nvim-treesitter-playground.internal".update_query(%d, %d)<CR>', bufnr, buf),
    { silent = true }
  )
  api.nvim_buf_attach(buf, false, {
    on_lines = utils.debounce(function()
      M.update_query(bufnr, buf)
    end, 1000),
  })

  local config = configs.get_module "playground"

  if config.persist_queries then
    M.read_saved_query(bufnr):then_(vim.schedule_wrap(function(lines)
      if #lines > 0 then
        api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      end
    end))
  else
    api.nvim_buf_set_lines(buf, 0, -1, false, {
      ";; Write your query here like `(node) @capture`,",
      ";; put the cursor under the capture to highlight the matches.",
    })
  end

  return buf
end

local function get_cache_path()
  return vim.fn.stdpath "cache" .. "/nvim_treesitter_playground"
end

local function get_filename(bufnr)
  return vim.fn.fnamemodify(vim.fn.bufname(bufnr), ":t")
end

function M.save_query_file(bufnr, query)
  local cache_path = get_cache_path()
  local filename = get_filename(bufnr)

  fs_stat(cache_path)
    :catch(function()
      return fs_mkdir(cache_path, 493)
    end)
    :then_(function()
      return fs_open(cache_path .. "/" .. filename .. "~", "w", 493)
    end)
    :then_(function(fd)
      return fs_write(fd, query, -1):then_(function()
        return fd
      end)
    end)
    :then_(function(fd)
      return fs_close(fd)
    end)
    :catch(function(err)
      print(err)
    end)
end

function M.read_saved_query(bufnr)
  local cache_path = get_cache_path()
  local filename = get_filename(bufnr)
  local query_path = cache_path .. "/" .. filename .. "~"

  return fs_open(query_path, "r", 438)
    :then_(function(fd)
      return fs_fstat(fd)
        :then_(function(stat)
          return fs_read(fd, stat.size, 0)
        end)
        :then_(function(data)
          return fs_close(fd):then_(function()
            return vim.split(data, "\n")
          end)
        end)
    end)
    :catch(function()
      return {}
    end)
end

function M.focus_language(bufnr)
  local node_entry = M.get_current_entry(bufnr)

  if not node_entry then
    return
  end

  M.update(bufnr, node_entry.language_tree)
end

function M.unfocus_language(bufnr)
  M._entries[bufnr].focused_language_tree = nil
  M.update(bufnr)
end

function M.highlight_playground_nodes(bufnr, nodes)
  local entry = M._entries[bufnr]
  local results = entry.results
  local display_buf = entry.display_bufnr
  local lines = {}
  local count = 0
  local node_map = utils.to_lookup_table(nodes, function(node)
    return node:id()
  end)

  if not results or not display_buf then
    return
  end

  for line, result in ipairs(results) do
    if node_map[result.node:id()] then
      table.insert(lines, line)
      count = count + 1
    end

    if count >= #nodes then
      break
    end
  end

  for _, lnum in ipairs(lines) do
    local buf_lines = api.nvim_buf_get_lines(display_buf, lnum - 1, lnum, false)

    if buf_lines[1] then
      vim.api.nvim_buf_add_highlight(display_buf, playground_ns, "TSPlaygroundFocus", lnum - 1, 0, -1)
    end
  end

  return lines
end

function M.highlight_playground_node_from_buffer(bufnr)
  M.clear_playground_highlights(bufnr)

  local entry = M._entries[bufnr]
  local display_buf = entry.display_bufnr

  if not display_buf then
    return
  end

  local node_at_point = get_node_at_cursor { include_anonymous = entry.include_anonymous_nodes }

  if not node_at_point then
    return
  end

  local lnums = M.highlight_playground_nodes(bufnr, { node_at_point })

  if lnums[1] then
    utils.for_each_buf_window(display_buf, function(window)
      api.nvim_win_set_cursor(window, { lnums[1], 0 })
    end)
  end
end

M._highlight_playground_node_debounced = utils.debounce(M.highlight_playground_node_from_buffer, get_update_time)

function M.get_current_entry(bufnr)
  local row, _ = unpack(api.nvim_win_get_cursor(0))
  local results = M._entries[bufnr].results

  return results and results[row]
end

function M.get_current_node(bufnr)
  local entry = M.get_current_entry(bufnr)

  return entry and entry.node
end

function M.highlight_node(bufnr)
  M.clear_highlights(bufnr)

  local node = M.get_current_node(bufnr)

  if not node then
    return
  end

  local start_row, start_col, _ = node:start()
  local last_row, last_col = utils.get_end_pos(bufnr)
  -- Set the cursor to the last column
  -- if the node starts at the EOF mark.
  if start_row > last_row then
    start_row = last_row
    start_col = last_col
  end

  M.highlight_nodes(bufnr, { node })

  utils.for_each_buf_window(bufnr, function(window)
    api.nvim_win_set_cursor(window, { start_row + 1, start_col })
  end)
end

function M.highlight_nodes(bufnr, nodes)
  for _, node in ipairs(nodes) do
    ts_utils.highlight_node(node, bufnr, playground_ns, "TSPlaygroundFocus")
  end
end

function M.goto_node(bufnr)
  local bufwin = vim.fn.win_findbuf(bufnr)[1]
  if bufwin then
    api.nvim_set_current_win(bufwin)
  else
    local node = M.get_current_node(bufnr)

    local win = api.nvim_get_current_win()
    vim.cmd "vsplit"
    api.nvim_win_set_buf(win, bufnr)
    api.nvim_set_current_win(win)

    ts_utils.goto_node(node)
    M.clear_highlights(bufnr)
  end
end

function M.update_query(bufnr, query_bufnr)
  local query = table.concat(api.nvim_buf_get_lines(query_bufnr, 0, -1, false), "\n")
  local matches = pl_query.parse(bufnr, query, M._entries[bufnr].focused_language_tree)
  local capture_by_color = {}
  local index = 1

  local config = configs.get_module "playground"

  if config.persist_queries then
    M.save_query_file(bufnr, query)
  end

  M._entries[bufnr].query_results = matches
  M._entries[bufnr].captures = {}
  M.clear_highlights(query_bufnr, query_hl_ns)
  M.clear_highlights(bufnr, query_hl_ns)

  for capture_match in ts_query.iter_group_results(query_bufnr, "captures") do
    table.insert(M._entries[bufnr].captures, capture_match.capture)

    local capture = ts_utils.get_node_text(capture_match.capture.name.node)[1]

    if not capture_by_color[capture] then
      capture_by_color[capture] = "TSPlaygroundCapture" .. index
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

  if not query_results then
    return
  end

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
  local node_at_point = get_node_at_cursor { include_anonymous = false }
  local captures = M._entries[bufnr].captures

  M.clear_highlights(bufnr)
  M.clear_highlights(M._entries[bufnr].display_bufnr)

  if not node_at_point or not captures then
    return
  end

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
  if not bufnr then
    return
  end

  namespace = namespace or playground_ns

  api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
end

function M.clear_playground_highlights(bufnr)
  M.clear_highlights(M._entries[bufnr].display_bufnr)
end

function M.toggle_query_editor(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

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

    api.nvim_win_set_option(0, "spell", false)
    api.nvim_win_set_option(0, "number", true)

    api.nvim_set_current_win(current_win)
  end
end

function M.open(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  local display_buf = setup_buf(bufnr)
  local current_window = api.nvim_get_current_win()

  M._entries[bufnr].display_bufnr = display_buf
  vim.cmd "vsplit"
  vim.cmd(string.format("buffer %d", display_buf))

  api.nvim_win_set_option(0, "spell", false)
  api.nvim_win_set_option(0, "number", false)
  api.nvim_win_set_option(0, "relativenumber", false)
  api.nvim_win_set_option(0, "cursorline", false)

  api.nvim_set_current_win(current_window)

  return display_buf
end

function M.toggle(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  local success, for_buf = pcall(api.nvim_buf_get_var, bufnr, query_buf_var_name)

  if success and for_buf then
    bufnr = for_buf
  end

  local display_buf = M._entries[bufnr].display_bufnr

  if display_buf and is_buf_visible(display_buf) then
    close_buf_windows(M._entries[bufnr].query_bufnr)
    close_buf_windows(display_buf)
  else
    M.open(bufnr)
  end
end

M.toggle_anonymous_nodes = make_entry_toggle("include_anonymous_nodes", { reprocess = true })
M.toggle_injected_languages = make_entry_toggle("suppress_injected_languages", { reprocess = true })
M.toggle_hl_groups = make_entry_toggle("include_hl_groups", { reprocess = true })
M.toggle_language_display = make_entry_toggle "include_language"

function M.update(bufnr, lang_tree)
  bufnr = bufnr or api.nvim_get_current_buf()
  lang_tree = lang_tree or resolve_lang_tree(bufnr)

  local entry = M._entries[bufnr]
  local display_buf = entry.display_bufnr

  -- Don't bother updating if the playground isn't shown
  if not display_buf or not is_buf_visible(display_buf) then
    return
  end

  entry.focused_language_tree = lang_tree

  local results = printer.process(bufnr, lang_tree, {
    include_anonymous_nodes = entry.include_anonymous_nodes,
    suppress_injected_languages = entry.suppress_injected_languages,
    include_hl_groups = entry.include_hl_groups,
  })

  M._entries[bufnr].results = results
  M.render(bufnr)
end

function M.render(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  local entry = M._entries[bufnr]
  local display_buf = entry.display_bufnr

  -- Don't bother updating if the playground isn't shown
  if not display_buf or not is_buf_visible(display_buf) then
    return
  end

  api.nvim_buf_set_lines(display_buf, 0, -1, false, printer.print_entries(entry.results))

  if entry.query_bufnr then
    M.update_query(bufnr, entry.query_bufnr)
  end

  if entry.include_language then
    printer.print_language(display_buf, entry.results)
  else
    printer.remove_language(display_buf)
  end

  if entry.include_hl_groups then
    printer.print_hl_groups(display_buf, entry.results)
  else
    printer.remove_hl_groups(display_buf)
  end
end

function M.show_help()
  local function filter(item, path)
    if path[#path] == vim.inspect.METATABLE then
      return
    end
    return item
  end
  print "Current keybindings:"
  print(vim.inspect(configs.get_module("playground").keybindings, { process = filter }))
end

function M.get_entries()
  return M._entries
end

function M.attach(bufnr)
  api.nvim_buf_attach(bufnr, true, {
    on_lines = vim.schedule_wrap(utils.debounce(function()
      M.update(bufnr)
    end, get_update_time)),
  })

  vim.cmd(string.format("augroup TreesitterPlayground_%d", bufnr))
  vim.cmd "au!"
  vim.cmd(string.format(
    -- luacheck: no max line length
    [[autocmd CursorMoved <buffer=%d> lua require'nvim-treesitter-playground.internal'._highlight_playground_node_debounced(%d)]],
    bufnr,
    bufnr
  ))
  vim.cmd(
    string.format(
      [[autocmd BufLeave <buffer=%d> lua require'nvim-treesitter-playground.internal'.clear_playground_highlights(%d)]],
      bufnr,
      bufnr
    )
  )
  vim.cmd "augroup END"
end

function M.detach(bufnr)
  clear_entry(bufnr)
  vim.cmd(string.format("autocmd! TreesitterPlayground_%d CursorMoved", bufnr))
  vim.cmd(string.format("autocmd! TreesitterPlayground_%d BufLeave", bufnr))
end

return M
