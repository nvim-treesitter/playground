local parsers = require 'nvim-treesitter.parsers'
local ts_utils = require 'nvim-treesitter.ts_utils'
local api = vim.api

local M = {}

local function print_tree(root, results, indent)
  local results = results or { lines = {}, nodes = {} }
  local indentation = indent or ""

  for node, field in root:iter_children() do
    if node:named() then
      local line
      if field then
        line = string.format("%s%s: %s [%d, %d] - [%d, %d]",
          indentation,
          field,
          node:type(),
          node:range())
      else
        line = string.format("%s%s [%d, %d] - [%d, %d]",
          indentation,
          node:type(),
          node:range())
      end

      table.insert(results.lines, line)
      table.insert(results.nodes, node)

      print_tree(node, results, indentation .. "  ")
    end
  end

  return results
end

function M.print(bufnr, lang)
  local bufnr = bufnr or api.nvim_get_current_buf()
  local parser = parsers.get_parser(bufnr, lang)

  if not parser then return end

  return print_tree(parser:parse():root())
end

return M
