local api = vim.api
local ts_utils = require "nvim-treesitter.ts_utils"
local highlighter = require "vim.treesitter.highlighter"

local M = {}

function M.debounce(fn, debounce_time)
  local timer = vim.loop.new_timer()
  local is_debounce_fn = type(debounce_time) == "function"

  return function(...)
    timer:stop()

    local time = debounce_time
    local args = { ... }

    if is_debounce_fn then
      time = debounce_time()
    end

    timer:start(
      time,
      0,
      vim.schedule_wrap(function()
        fn(unpack(args))
      end)
    )
  end
end

--- Determines if {range_1} contains (inclusive) {range_2}
---
---@param range table
---@param range table
---
---@return boolean True if {range_1} contains {range_2}
function M.range_contains(range_1, range_2)
  return (range_1[1] < range_2[1] or (range_1[1] == range_2[1] and range_1[2] <= range_2[2]))
    and (range_1[3] > range_2[3] or (range_1[3] == range_2[3] and range_1[4] >= range_2[4]))
end

--- Determines if {range_1} intersects (inclusive) {range_2}
---
---@param range table
---@param range table
---
---@return boolean True if {range_1} intersects {range_2}
function M.range_intersects(range_1, range_2)
  return (
    range_1[1] < range_2[3]
    or (
      range_1[1] == range_2[3]
      and (range_1[2] < range_2[4] or (range_1[2] == range_2[4] and range_1[4] == range_2[4]))
    )
  )
    and (
      range_2[1] < range_1[3]
      or (
        range_2[1] == range_1[3]
        and (range_2[2] < range_1[4] or (range_2[2] == range_1[4] and range_2[4] == range_1[4]))
      )
    )
end

--- Invokes the callback for each active highlighter's |LanguageTree|s recursively.
---
--- Note: This includes each root tree's child trees as well.
---
---@param bufnr number Buffer number (0 for current buffer)
---@param fn function(buf_highlighter: TSHighlighter, tstree: tsnode, tree: LanguageTree)
function M.for_each_hl_tree(bufnr, fn)
  if bufnr == 0 then
    bufnr = a.nvim_get_current_buf()
  end
  local buf_highlighter = highlighter.active[bufnr]
  if not buf_highlighter then
    return
  end
  return buf_highlighter.tree:for_each_tree(function(tstree, tree)
    return fn(buf_highlighter, tstree, tree)
  end, true)
end

--- Invokes the callback for each capture inside {node} that is contained in {range}.
---
---@param query (Query|nil) Parsed query (callback will not be invoked if nil)
---@param node userdata |tsnode| under which the search will occur
---@param source (number|string) Source buffer or string to extract text from
---@param range range Boundaries for the search (inclusive)
---@param fn function(capture_id: string, captured_node: tsnode, capture_metadata: table)
function M.for_each_query_capture_for_range(query, node, source, range, fn)
  -- Only worry about nodes within the range
  if query == nil or not M.range_intersects({ node:range() }, range) then
    return
  end

  for capture_id, captured_node, capture_metadata in query:iter_captures(node, source, range[1], range[3] + 1) do
    if M.range_contains({ captured_node:range() }, range) then
      fn(capture_id, captured_node, capture_metadata)
    end
  end
end

function M.get_hl_groups_at_position(bufnr, row, col)
  local range = { row, col, row, col }
  local matches = {}
  M.for_each_hl_tree(bufnr, function(buf_highlighter, tstree, tree)
    if not tstree then
      return
    end

    local hl_query = buf_highlighter:get_query(tree:lang())
    M.for_each_query_capture_for_range(
      hl_query:query(),
      tstree:root(),
      buf_highlighter.bufnr,
      range,
      function(capture_id, captured_node, capture_metadata)
        local capture_hl = hl_query.hl_cache[capture_id]
        if capture_hl then
          local capture_name = hl_query:query().captures[capture_id]
          table.insert(matches, { capture = capture_name, priority = capture_metadata.priority })
        end
      end
    )
  end)
  return matches
end

function M.for_each_buf_window(bufnr, fn)
  if not api.nvim_buf_is_loaded(bufnr) then
    return
  end

  for _, window in ipairs(vim.fn.win_findbuf(bufnr)) do
    fn(window)
  end
end

function M.to_lookup_table(list, key_mapper)
  local result = {}

  for i, v in ipairs(list) do
    local key = v

    if key_mapper then
      key = key_mapper(v, i)
    end

    result[key] = v
  end

  return result
end

function M.node_contains(node, range)
  return M.range_contains({ node:range() }, range)
end

--- Returns a tuple with the position of the last line and last column (0-indexed).
function M.get_end_pos(bufnr)
  local bufnr = bufnr or api.nvim_get_current_buf()
  local last_row = api.nvim_buf_line_count(bufnr) - 1
  local last_line = api.nvim_buf_get_lines(bufnr, last_row, last_row + 1, true)[1]
  local last_col = last_line and #last_line or 0
  return last_row, last_col
end

return M
