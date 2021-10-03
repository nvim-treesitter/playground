local highlighter = require "vim.treesitter.highlighter"
local ts_utils = require "nvim-treesitter.ts_utils"
local has_semantic_tokens, semantic_tokens = pcall(require, "vim.lsp.semantic_tokens")

local M = {}

function M.get_semantic_tokens()
  local buf = vim.api.nvim_get_current_buf()
  local ft = vim.api.nvim_buf_get_option(buf, "filetype")
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1
  local tokens = semantic_tokens.get(buf)
  local matches = {}

  for client_id, client_tokens in pairs(tokens) do
    local line_tokens = client_tokens[row + 1] or {}
    local num_client_matches = 0
    table.insert(matches, "# LSP Semantic Tokens (Client " .. client_id .. ")")
    for _, token in ipairs(line_tokens) do
      if token.start_char <= col and col < token.start_char + token.length then
        local mappings = {}
        if semantic_tokens.token_map[token.type] then
          table.insert(mappings, ft .. semantic_tokens.token_map[token.type])
        end
        for _, m in pairs(token.modifiers) do
          local hl = semantic_tokens.modifiers_map[m]
          -- modifiers can have a per-type mapping
          -- e.g. readonly = { variable = "ReadOnlyVariable" }
          if type(hl) == "table" then
            hl = hl[token.type]
          end
          if hl then
            table.insert(mappings, ft .. hl)
          end
        end
        num_client_matches = num_client_matches + 1
        table.insert(
          matches,
          "* "
            .. token.type
            .. ", modifiers: "
            .. vim.inspect(token.modifiers)
            .. " -> "
            .. table.concat(mappings, ", ")
            .. " "
        )
      end
      if num_client_matches == 0 then
        table.insert(matches, "* No tokens under cursor")
      end
    end
    table.insert(matches, "")
  end
  return matches
end

function M.get_treesitter_hl()
  local buf = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1

  local self = highlighter.active[buf]

  if not self then
    return {}
  end

  local matches = {}

  self.tree:for_each_tree(function(tstree, tree)
    if not tstree then
      return
    end

    local root = tstree:root()
    local root_start_row, _, root_end_row, _ = root:range()

    -- Only worry about trees within the line range
    if root_start_row > row or root_end_row < row then
      return
    end

    local query = self:get_query(tree:lang())

    -- Some injected languages may not have highlight queries.
    if not query:query() then
      return
    end

    local iter = query:query():iter_captures(root, self.bufnr, row, row + 1)

    for capture, node, metadata in iter do
      local hl = query.hl_cache[capture]

      if hl and ts_utils.is_in_node_range(node, row, col) then
        local c = query._query.captures[capture] -- name of the capture in the query
        if c ~= nil then
          local general_hl = query:_get_hl_from_capture(capture)
          local line = "* **@" .. c .. "** -> " .. hl
          if general_hl ~= hl then
            line = line .. " -> **" .. general_hl .. "**"
          end
          if metadata.priority then
            line = line .. " *(priority " .. metadata.priority .. ")*"
          end
          table.insert(matches, line)
        end
      end
    end
  end, true)
  return matches
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

  if has_semantic_tokens then
    local matches = M.get_semantic_tokens()
    vim.list_extend(lines, matches)
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
