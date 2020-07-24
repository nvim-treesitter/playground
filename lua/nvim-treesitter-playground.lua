local queries = require "nvim-treesitter.query"

local M = {}

function M.init()
  require "nvim-treesitter".define_modules {
    playground = {
      module_path = "nvim-treesitter-playground.internal",
      keymaps = {
        open = 'gtd'
      },
      updatetime = 25
    }
  }
end

return M
