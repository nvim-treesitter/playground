local parsers = require "nvim-treesitter.parsers"
local M = {}

function M.init()
  require("nvim-treesitter").define_modules {
    playground = {
      module_path = "nvim-treesitter-playground.internal",
      updatetime = 25,
      persist_queries = false,
      keybindings = {
        toggle_query_editor = "o",
        toggle_hl_groups = "i",
        toggle_injected_languages = "t",
        toggle_anonymous_nodes = "a",
        toggle_language_display = "I",
        focus_language = "f",
        unfocus_language = "F",
        update = "R",
        goto_node = "<cr>",
        show_help = "?",
      },
    },
    query_linter = {
      module_path = "nvim-treesitter-playground.query_linter",
      use_virtual_text = true,
      lint_events = { "BufWrite", "CursorHold" },
      is_supported = function(lang)
        return lang == "query" and parsers.has_parser "query"
      end,
    },
  }

  vim.cmd [[
    command! TSHighlightCapturesUnderCursor :lua require'nvim-treesitter-playground.hl-info'.show_hl_captures()<cr>
  ]]
end

return M
