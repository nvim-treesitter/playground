local ts_query = require 'nvim-treesitter.query'
local parsers = require 'nvim-treesitter.parsers'
local locals = require 'nvim-treesitter.locals'
local api = vim.api

local M = {}

function M.parse(bufnr, query)
  local lang = api.nvim_buf_get_option(bufnr, 'ft')
  local success, parsed_query = pcall(function() return vim.treesitter.parse_query(lang, query) end)

  if not success then return {} end

  local parser = parsers.get_parser(bufnr, lang)
  local root = parser:parse()[1]:root()
  local start_row, _, end_row, _ = root:range()
  local results = {}

  for match in ts_query.iter_prepared_matches(parsed_query, root, bufnr, start_row, end_row) do
    locals.recurse_local_nodes(match, function(_, node, path)
      table.insert(results, { node = node, tag = path })
    end)
  end

  return results
end

return M
