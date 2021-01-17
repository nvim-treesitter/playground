local ts_query = require 'nvim-treesitter.query'
local parsers = require 'nvim-treesitter.parsers'
local locals = require 'nvim-treesitter.locals'

local M = {}

function M.parse(bufnr, query, lang_tree)
  lang_tree = lang_tree or parsers.get_parser(bufnr)

  local success, parsed_query = pcall(function()
    return vim.treesitter.parse_query(lang_tree:lang(), query)
  end)

  if not success then return {} end

  local results = {}

  for _, tree in ipairs(lang_tree:trees()) do
    local root = tree:root()
    local start_row, _, end_row, _ = root:range()

    for match in ts_query.iter_prepared_matches(parsed_query, root, bufnr, start_row, end_row) do
      locals.recurse_local_nodes(match, function(_, node, path)
        table.insert(results, { node = node, tag = path })
      end)
    end
  end

  return results
end

return M
