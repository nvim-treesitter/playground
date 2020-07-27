local M = {}

function M.debounce(fn, debounce_time)
  local timer = vim.loop.new_timer()
  local is_debounce_fn = type(debounce_time) == 'function'

  return function(...)
    timer:stop()

    local time = debounce_time
    local args = {...}

    if is_debounce_fn then
      time = debounce_time()
    end

    timer:start(time, 0, vim.schedule_wrap(function() fn(unpack(args)) end))
  end
end

function M.for_each_buf_window(bufnr, fn)
  for _, window in ipairs(vim.fn.win_findbuf(bufnr)) do
    fn(window)
  end
end

return M
