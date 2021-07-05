local api = vim.api
local queries = require "nvim-treesitter.query"
local parsers = require "nvim-treesitter.parsers"
local ts_utils = require "nvim-treesitter.ts_utils"
local utils = require "nvim-treesitter.utils"
local configs = require "nvim-treesitter.configs"

local hl_namespace = api.nvim_create_namespace "nvim-playground-lints"
local ERROR_HL = "TSQueryLinterError"
local MAGIC_NODE_NAMES = { "_", "ERROR" }
local playground_module = require "nvim-treesitter-playground.internal"

local M = {}

M.lints = {}
M.use_virtual_text = true
M.lint_events = { "BufWrite", "CursorHold" }

local function lint_node(node, buf, error_type, complete_message)
  if error_type ~= "Invalid Query" then
    ts_utils.highlight_node(node, buf, hl_namespace, ERROR_HL)
  end
  local node_text = table.concat(ts_utils.get_node_text(node, buf), " ")
  local error_text = complete_message or error_type .. ": " .. node_text
  local error_range = { node:range() }
  if M.use_virtual_text then
    api.nvim_buf_set_virtual_text(buf, hl_namespace, error_range[1], { { error_text, ERROR_HL } }, {})
  end
  table.insert(M.lints[buf], { type = error_type, range = error_range, message = error_text, node_text = node_text })
end

local function table_contains(predicate, table)
  for _, elt in pairs(table) do
    if predicate(elt) then
      return true
    end
  end
  return false
end

local function query_lang_from_playground_buf(buf)
  for lang_buf, entry in pairs(playground_module.get_entries() or {}) do
    if entry.query_bufnr == buf then
      if entry.focused_language_tree then
        return entry.focused_language_tree:lang()
      end

      return parsers.get_buf_lang(lang_buf)
    end
  end
end

function M.guess_query_lang(buf)
  local filename = api.nvim_buf_get_name(buf)
  local ok, query_lang = pcall(vim.fn.fnamemodify, filename, ":p:h:t")
  query_lang = filename ~= "" and query_lang
  query_lang = ok and query_lang
  if not query_lang then
    query_lang = query_lang_from_playground_buf(buf)
  end
  return parsers.ft_to_lang(query_lang)
end

function M.lint(query_buf)
  query_buf = query_buf or api.nvim_get_current_buf()
  M.clear_virtual_text(query_buf)
  M.lints[query_buf] = {}

  local query_lang = M.guess_query_lang(query_buf)

  local ok, parser_info = pcall(vim.treesitter.inspect_language, query_lang)

  parser_info = ok and parser_info

  local matches = queries.get_matches(query_buf, "query-linter-queries")

  for _, m in pairs(matches) do
    local error_node = utils.get_at_path(m, "error.node")

    if error_node then
      lint_node(error_node, query_buf, "Syntax Error")
    end

    local toplevel_node = utils.get_at_path(m, "toplevel-query.node")
    if toplevel_node and query_lang then
      local query_text = table.concat(ts_utils.get_node_text(toplevel_node), "\n")
      local err
      ok, err = pcall(vim.treesitter.parse_query, query_lang, query_text)
      if not ok then
        lint_node(toplevel_node, query_buf, "Invalid Query", err)
      end
    end

    if parser_info and parser_info.symbols then
      local named_node = utils.get_at_path(m, "named_node.node")
      local anonymous_node = utils.get_at_path(m, "anonymous_node.node")
      local node = named_node or anonymous_node
      if node then
        local node_type = ts_utils.get_node_text(node)[1]

        if anonymous_node then
          node_type = node_type:gsub('"(.*)".*$', "%1"):gsub("\\(.)", "%1")
        end

        local is_named = named_node ~= nil

        local found = vim.tbl_contains(MAGIC_NODE_NAMES, node_type)
          or table_contains(function(t)
            return node_type == t[1] and is_named == t[2]
          end, parser_info.symbols)

        if not found then
          lint_node(node, query_buf, "Invalid Node Type")
        end
      end

      local field_node = utils.get_at_path(m, "field.node")

      if field_node then
        local field_name = ts_utils.get_node_text(field_node)[1]
        local found = vim.tbl_contains(parser_info.fields, field_name)
        if not found then
          lint_node(field_node, query_buf, "Invalid Field")
        end
      end
    end
  end
  return M.lints[query_buf]
end

function M.clear_virtual_text(buf)
  api.nvim_buf_clear_namespace(buf, hl_namespace, 0, -1)
end

function M.attach(buf, _)
  M.lints[buf] = {}

  local config = configs.get_module "query_linter"
  M.use_virtual_text = config.use_virtual_text
  M.lint_events = config.lint_events

  vim.cmd(string.format("augroup TreesitterPlaygroundLint_%d", buf))
  vim.cmd "au!"
  for _, e in pairs(M.lint_events) do
    vim.cmd(
      string.format(
        [[autocmd! %s <buffer=%d> lua require'nvim-treesitter-playground.query_linter'.lint(%d)]],
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
