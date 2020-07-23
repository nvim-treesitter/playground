local parsers = require 'nvim-treesitter.parsers'
local ts_utils = require 'nvim-treesitter.ts_utils'
local api = vim.api

local M = {}

function M.print_node(node, results, options)
  local options = options or {}
  local level = options.level or 0
  local indent_char = options.indent_char or '  '
  local type = node:type()
  local start_row, start_col, end_row, end_col = node:range()
  local results = results or { lines = {}, nodes = {} }

  table.insert(results.lines, string.rep(indent_char, level) .. string.format("%s [%d, %d] - [%d, %d])", type, start_col, start_row, end_col, end_row))
  table.insert(results.nodes, node)

  local node_count = node:named_child_count()

  for i = 0, node:named_child_count() - 1, 1 do
    M.print_node(node:named_child(i), results, vim.tbl_extend("force", options, { level = level + 1 }))
  end

  return results
end

function M.print(bufnr, lang)
  local bufnr = bufnr or api.nvim_get_current_buf()
  local parser = parsers.get_parser(bufnr, lang)

  if not parser then return end

  return M.print_node(parser:parse():root())
end

return M
