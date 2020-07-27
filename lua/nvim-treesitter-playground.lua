local queries = require "nvim-treesitter.query"

local M = {}

function M.init()
  require "nvim-treesitter".define_modules {
    playground = {
      module_path = "nvim-treesitter-playground.internal",
      updatetime = 25
    }
  }
end

return M
