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
  local result = {}

  local function add_to_result(matches, source)
    if #matches == 0 then
      return
    end

    table.insert(result, "# " .. source)

    for _, match in ipairs(matches) do
      table.insert(result, match)
    end
  end

  if highlighter.active[buf] then
    local matches = M.get_treesitter_hl()
    add_to_result(matches, "Treesitter")
  end

  if vim.b.current_syntax ~= nil or #result == 0 then
    local matches = M.get_syntax_hl()
    add_to_result(matches, "Syntax")
  end

  if #result == 0 then
    table.insert(result, "* No highlight groups found")
  end

  vim.lsp.util.open_floating_preview(result, "markdown", { border = "single", pad_left = 4, pad_right = 4 })
end

-- Show Node at Cursor
---@param opts? table with optional fields
---             - full_path: (boolean, default false) show full path to current node
---             - show_range: (boolean, default true) show range of current node
---             - include_anonymous: (boolean, default false) include anonymous node
---             - highlight_node: (boolean, default true) highlight the current node
---             - hl_group: (string, default "TSPlaygroundFocus") name of group
--- @return number|nil bufnr number
function M.show_ts_node(opts)
  opts = vim.tbl_deep_extend("keep", opts or {}, {
    full_path = false,
    show_range = true,
    include_anonymous = false,
    highlight_node = true,
    hl_group = "TSPlaygroundFocus",
  })

  if not parsers.has_parser() then
    return
  end

  -- Get Full Path to node
  -- @param node
  -- @param array?
  -- @return string
  local function get_full_path(node, array)
    local parent = node:parent()
    if parent == nil then
      if array == nil then
        return node:type()
      end
      local reverse = vim.tbl_map(function(index)
        return array[#array + 1 - index]:type()
      end, vim.tbl_keys(array))
      return table.concat(reverse, " -> ")
    end
    return get_full_path(parent, vim.list_extend(array or {}, { node }))
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local range = { cursor[1] - 1, cursor[2], cursor[1] - 1, cursor[2] }

  local bufnr = 0
  local root_lang_tree = parsers.get_parser(bufnr)
  local lang_tree = root_lang_tree:language_for_range(range)

  local lines = { "# Treesitter" }
  local node_under_cursor

  for _, tree in ipairs(lang_tree:trees()) do
    local root = tree:root()
    if root and utils.range_contains({ root:range() }, range) then
      local node = root:named_descendant_for_range(range[1], range[2], range[3], range[4])
      local path = opts.full_path and get_full_path(node) or node:type()

      node_under_cursor = node

      vim.list_extend(lines, {
        "* Parser: " .. lang_tree:lang(),
        string.format("* %s: ", opts.full_path and "Node path" or "Node") .. path,
      })

      if opts.include_anonymous then
        local anonymous_node = root:descendant_for_range(range[1], range[2], range[3], range[4])
        vim.list_extend(lines, {
          " - Anonymous: " .. anonymous_node:type(),
        })
      end

      if opts.show_range then
        local srow, scol, erow, ecol = ts_utils.get_vim_range({ node:range() }, bufnr)

        vim.list_extend(lines, {
          "* Range: ",
          "  - Start row: " .. srow,
          "  - End row: " .. erow,
          "  - Start col: " .. scol,
          "  - End col: " .. ecol,
        })
      end
    end
  end

  if not node_under_cursor then
    lines[#lines + 1] = "* Node not found"
  end

  if opts.highlight_node and node_under_cursor then
    local ns = vim.api.nvim_create_namespace "nvim-treesitter-current-node"

    ts_utils.highlight_node(node_under_cursor, bufnr, ns, opts.hl_group)
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = vim.api.nvim_create_augroup("TSNodeUnderCursor", {}),
      buffer = bufnr,
      callback = function()
        require("nvim-treesitter-playground.internal").clear_highlights(bufnr, ns)
      end,
      desc = "TSPlayground: clear highlights",
    })
  end

  return vim.lsp.util.open_floating_preview(lines, "markdown", { border = "single", pad_left = 4, pad_right = 4 })
end

return M
