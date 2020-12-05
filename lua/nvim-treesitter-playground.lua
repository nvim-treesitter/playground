local parsers = require 'nvim-treesitter.parsers'
local M = {}

vim.cmd [[
  command! TSHighlightCapturesUnderCursor :lua require'nvim-treesitter-playground.hl-info'.show_hl_captures()<cr>
]]

function M.init()
  require "nvim-treesitter".define_modules {
    playground = {
      module_path = "nvim-treesitter-playground.internal",
      updatetime = 25,
      persist_queries = false
    },
    query_linter = {
      module_path = "nvim-treesitter-playground.query_linter",
      is_supported = function(lang)
        return lang == 'query' and parsers.has_parser('query')
      end,
    },
  }
end

return M
