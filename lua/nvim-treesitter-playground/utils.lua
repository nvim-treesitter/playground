local api = vim.api

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
  local start_row, start_col, end_row, end_col = node:range()
  local start_fits = start_row < range[1] or (start_row == range[1] and start_col <= range[2])
  local end_fits = end_row > range[3] or (end_row == range[3] and end_col >= range[4])

  return start_fits and end_fits
end

--- Returns a tuple with the position of the last line and last column (0-indexed).
function M.get_end_pos(bufnr)
  local bufnr = bufnr or api.nvim_get_current_buf()
  local last_row = api.nvim_buf_line_count(bufnr) - 1
  local last_line = api.nvim_buf_get_lines(bufnr, last_row, last_row + 1, true)[1]
  local last_col = #last_line
  return last_row, last_col
end

return M
