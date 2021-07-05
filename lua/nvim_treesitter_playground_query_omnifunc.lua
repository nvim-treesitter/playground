local query_linter = require "nvim-treesitter-playground.query_linter"
local tsc = require "vim.treesitter.query"

local M = {}

function M.omnifunc(findstart, base)
  if findstart == 1 then
    local start = vim.fn.col "." - 1
    local result = vim.fn.matchstrpos(vim.fn.getline("."):sub(1, start), '\\v(["#\\-]|\\w)*$')
    return result[2]
  end

  local buf = vim.api.nvim_get_current_buf()
  local query_lang = query_linter.guess_query_lang(buf)

  local ok, parser_info = pcall(vim.treesitter.inspect_language, query_lang)

  if ok then
    local items = {}
    for _, f in pairs(parser_info.fields) do
      if f:find(base, 1, true) == 1 then
        table.insert(items, f .. ":")
      end
    end
    for _, p in pairs(tsc.list_predicates()) do
      local text = "#" .. p
      local found = text:find(base, 1, true)
      if found and found <= 2 then -- with or without '#'
        table.insert(items, text)
      end
      text = "#not-" .. p
      found = text:find(base, 1, true)
      if found and found <= 2 then -- with or without '#'
        table.insert(items, text)
      end
    end
    for _, s in pairs(parser_info.symbols) do
      local text = s[2] and s[1] or '"' .. vim.fn.escape(s[1], "\\") .. '"'
      if text:find(base, 1, true) == 1 then
        table.insert(items, text)
      end
    end
    return { words = items, refresh = "always" }
  else
    return -2
  end
end

return M
