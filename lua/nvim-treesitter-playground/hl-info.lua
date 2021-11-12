local utils = require "nvim-treesitter-playground.utils"
local highlighter = require "vim.treesitter.highlighter"

local M = {}

function M.get_treesitter_hl()
  local buf = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1

  local results = utils.get_hl_groups_at_position(buf, row, col)
  return results
end

function M.get_syntax_hl()
  local line = vim.fn.line "."
  local col = vim.fn.col "."
  local matches = {}
  for _, i1 in ipairs(vim.fn.synstack(line, col)) do
    local i2 = vim.fn.synIDtrans(i1)
    local n1 = vim.fn.synIDattr(i1, "name")
    local n2 = vim.fn.synIDattr(i2, "name")
    table.insert(matches, "* " .. n1 .. " -> **" .. n2 .. "**")
  end
  return matches
end

function M.show_hl_captures()
  local buf = vim.api.nvim_get_current_buf()
  local lines = {}

  local function show_matches(matches)
    if #matches == 0 then
      table.insert(lines, "* No highlight groups found")
    end
    for _, line in ipairs(matches) do
      table.insert(lines, line)
    end
    table.insert(lines, "")
  end

  if highlighter.active[buf] then
    table.insert(lines, "# Treesitter")
    local matches = M.get_treesitter_hl()
    show_matches(matches)
  end

  if vim.b.current_syntax then
    table.insert(lines, "# Syntax")
    local matches = M.get_syntax_hl()
    show_matches(matches)
  end

  vim.lsp.util.open_floating_preview(lines, "markdown", { border = "single", pad_left = 4, pad_right = 4 })
end

return M
