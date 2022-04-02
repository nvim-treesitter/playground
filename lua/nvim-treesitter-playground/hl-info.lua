local utils = require "nvim-treesitter-playground.utils"
local highlighter = require "vim.treesitter.highlighter"
local ts_utils = require "nvim-treesitter.ts_utils"
local parsers = require "nvim-treesitter.parsers"

local M = {}

function M.get_treesitter_hl()
  local bufnr = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1

  local results = utils.get_hl_groups_at_position(bufnr, row, col)
  local highlights = {}
  for _, hl in pairs(results) do
    local line = "* **@" .. hl.capture .. "**"
    if hl.specific then
      line = line .. " -> **" .. hl.specific .. "**"
    end
    if hl.general then
      line = line .. " -> **" .. hl.general .. "**"
    end
    if hl.priority then
      line = line .. "(" .. hl.priority .. ")"
    end
    table.insert(highlights, line)
  end
  return highlights
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

-- Show Node at Cursor
-- @param border_opts table
-- @return bufnr
function M.show_ts_node(border_opts)
  -- TODO: ok
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] - 1
  local col = cursor[2]

  local root_lang_tree = parsers.get_parser(0)
  local lang_tree = root_lang_tree:language_for_range { line, col, line, col }

  local lines

  for _, tree in ipairs(lang_tree:trees()) do
    local root = tree:root()
    if root and ts_utils.is_in_node_range(root, line, col) then
      local node = root:named_descendant_for_range(line, col, line, col)
      local srow, scol, erow, ecol = node:range()
      lines = {
        "# Treesitter",
        "* Parser: " .. lang_tree:lang(),
        "* Node: " .. node:type(),
        "* Range: ",
        "  - Start row: " .. srow + 1,
        "  - End row: " .. erow + 1,
        "  - Start Col: " .. scol + 1,
        "  - End col: " .. ecol,
      }
    else
      lines = { "# Treesitter", "* Node not found" }
    end
  end

  return vim.lsp.util.open_floating_preview(
    lines,
    "markdown",
    border_opts or { border = "single", pad_left = 4, pad_right = 4 }
  )
end

return M
