local parsers = require "nvim-treesitter.parsers"
local queries = require'nvim-treesitter.query'
local ts_utils = require'nvim-treesitter.ts_utils'
local utils = require'nvim-treesitter.utils'

local hlmap = vim.treesitter.highlighter.hl_map

local M = {}

function M.show_hl_captures()
  local bufnr = vim.api.nvim_get_current_buf()
  local lang = parsers.get_buf_lang(bufnr)
  local hl_captures = vim.tbl_keys(hlmap)

  if not lang then return end

  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1

  local matches = {}
  for m in queries.iter_group_results(bufnr, 'highlights') do
    for _, c in pairs(hl_captures) do
      local node = utils.get_at_path(m, c..'.node')
      if node and ts_utils.is_in_node_range(node, row, col) then
        table.insert(matches, '@'..c..' -> '..hlmap[c])
      end
    end
  end
  if #matches == 0 then
    matches = {"No tree-sitter matches found!"}
  end
  vim.lsp.util.open_floating_preview(matches, "treesitter-hl-captures")
end

return M
