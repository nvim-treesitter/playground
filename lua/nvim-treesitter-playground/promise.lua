local M = {}
local luv = vim.loop

function M.promisify(fn)
  return function(...)
    local args = { ... }
    return M.new(function(resolve, reject)
      table.insert(args, function(err, v)
        if err then
          return reject(err)
        end

        resolve(v)
      end)

      fn(unpack(args))
    end)
  end
end

local function set_timeout(timeout, fn)
  local timer = luv.new_timer()

  timer:start(timeout, 0, function()
    timer:stop()
    timer:close()
    fn()
  end)

  return timer
end

function M.new(sink)
  local p = setmetatable({
    result = nil,
    is_resolved = false,
    is_errored = false,
    cbs = {},
    err_cbs = {},
  }, {
    __index = M,
  })

  p._resolve = function(v)
    p:_set_result(v, false)
  end
  p._reject = function(err)
    p:_set_result(err, true)
  end

  local success, err = pcall(function()
    sink(p._resolve, p._reject)
  end)

  if not success then
    p._reject(err)
  end

  return p
end

function M:then_(on_success, on_error)
  local p = self

  return M.new(function(resolve, reject)
    table.insert(p.cbs, function(result)
      if not on_success then
        return resolve(result)
      end

      local success, res = pcall(function()
        resolve(on_success(result))
      end)

      if not success then
        reject(res)
      end

      return res
    end)

    table.insert(p.err_cbs, function(result)
      if not on_error then
        return reject(result)
      end

      local success, res = pcall(function()
        resolve(on_error(result))
      end)

      if not success then
        reject(res)
      end

      return res
    end)

    p:_exec_handlers()
  end)
end

function M:catch(on_error)
  return self:then_(nil, on_error)
end

function M:_exec_handlers()
  if self.is_resolved then
    for _, cb in ipairs(self.cbs) do
      cb(self.result)
    end

    self.cbs = {}
    self.err_cbs = {}
  elseif self.is_errored then
    for _, cb in ipairs(self.err_cbs) do
      cb(self.result)
    end

    self.cbs = {}
    self.err_cbs = {}
  end
end

function M:_set_result(result, errored)
  local p = self

  set_timeout(0, function()
    if p.is_resolved or p.is_errored then
      return
    end

    if M.is_promise(result) then
      return result:then_(p._resolve, p._reject)
    end

    p.result = result

    if errored then
      p.is_errored = true
    else
      p.is_resolved = true
    end

    p:_exec_handlers()
  end)
end

function M.is_promise(v)
  return type(v) == "table" and type(v.then_) == "function"
end

return M
