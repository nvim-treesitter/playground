local api = vim.api
local queries = require "nvim-treesitter.query"
local ts_utils = require "nvim-treesitter.ts_utils"
local utils = require "nvim-treesitter.utils"
local configs = require'nvim-treesitter.configs'

local hl_namespace = api.nvim_create_namespace("nvim-playground-lints")
local ERROR_HL = "TSQueryLinterError"
local MAGIC_NODE_NAMES = {"_", "ERROR"}

local M = {}

M.lints = {}
M.use_virtual_text = true
M.lint_events = {"BufWrite", "CursorHold"}

local function lint_node(node, buf, message_prefix)
  ts_utils.highlight_node(node, buf, hl_namespace, ERROR_HL)
  local node_text = table.concat(ts_utils.get_node_text(node, buf), " ")
  local error_text = message_prefix .. ": " .. node_text
  local error_range = {node:range()}
  if M.use_virtual_text then
    api.nvim_buf_set_virtual_text(buf, hl_namespace, error_range[1], {{error_text, ERROR_HL}}, {})
  end
  table.insert(M.lints[buf], {type = message_prefix, range = error_range, message = node_text})
end

local function table_contains(predicate, table)
  for _, elt in pairs(table) do
    if predicate(elt) then
      return true
    end
  end
  return false
end

function M.lint(buf)
  buf = buf or api.nvim_get_current_buf()
  M.clear_virtual_text(buf)
  M.lints[buf] = {}

  local filename = api.nvim_buf_get_name(buf)
  local ok, query_lang = pcall(vim.fn.fnamemodify, filename, ":p:h:t")
  local query_lang = ok and query_lang
  local ok, parser_info = pcall(vim.treesitter.inspect_language, query_lang)
  local parser_info = ok and parser_info

  local matches = queries.get_matches(buf, "query-linter-queries")

  for _, m in pairs(matches) do
    local error_node = utils.get_at_path(m, "error.node")

    if error_node then
      lint_node(error_node, buf, "Syntax Error")
    end

    if parser_info and parser_info.symbols then
      local named_node = utils.get_at_path(m, "named_node.node")
      local anonymous_node = utils.get_at_path(m, "anonymous_node.node")

      if named_node or anonymous_node then
        local node = named_node or anonymous_node
        local node_type = ts_utils.get_node_text(node)[1]

        if anonymous_node then
          node_type = node_type.sub(2, -2)
        end

        local found =
          vim.tbl_contains(MAGIC_NODE_NAMES, node_type) or
          table_contains(
            function(t)
              return node_type == t[1]
            end,
            parser_info.symbols
          )
        if not found then
          lint_node(node, buf, "Invalid Node Type")
        end
      end
    end

    local field_node = utils.get_at_path(m, "field.node")

    if field_node then
      local field_name = ts_utils.get_node_text(field_node)[1]
      local found = vim.tbl_contains(parser_info.fields, field_name)
      if not found then
        lint_node(field_node, buf, "Invalid Field")
      end
    end
  end
end

function M.clear_virtual_text(buf)
  api.nvim_buf_clear_namespace(buf, hl_namespace, 0, -1)
end

function M.attach(buf, _)
  M.lints[buf] = {}

  local config = configs.get_module("query_linter")
  M.use_virtual_text = config.use_virtual_text
  M.lint_events = config.lint_events

  vim.cmd(string.format("augroup TreesitterPlaygroundLint_%d", buf))
  vim.cmd "au!"
  for _, e in pairs(M.lint_events) do
    vim.cmd(
      string.format(
        [[autocmd %s <buffer=%d> lua require'nvim-treesitter-playground.query_linter'.lint(%d)]],
        e,
        buf,
        buf
      )
    )
  end
  vim.cmd "augroup END"
end

function M.detach(buf)
  M.lints[buf] = nil
  M.clear_virtual_text(buf)
  for _, e in pairs(M.lint_events) do
    vim.cmd(string.format("autocmd! TreesitterPlaygroundLint_%d %s", buf, e))
  end
end

return M
