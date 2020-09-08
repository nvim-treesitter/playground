local M = {}

function M.init()
  require "nvim-treesitter".define_modules {
    playground = {
      module_path = "nvim-treesitter-playground.internal",
      updatetime = 25,
      persist_queries = false
    }
  }
end

return M
