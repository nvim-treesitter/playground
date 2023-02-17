local api = vim.api
local queries = require "nvim-treesitter.query"
local parsers = require "nvim-treesitter.parsers"
local utils = require "nvim-treesitter.utils"
local configs = require "nvim-treesitter.configs"

local namespace = api.nvim_create_namespace "nvim-playground-lints"
local MAGIC_NODE_NAMES = { "_", "ERROR" }
local playground_module = require "nvim-treesitter-playground.internal"

local M = {}

M.lints = {}
M.use_diagnostics = true
M.lint_events = { "BufWrite", "CursorHold" }

local function show_lints(buf, lints)
  if M.use_diagnostics then
    local diagnostics = vim.tbl_map(function(lint)
      return {
        lnum = lint.range[1], end_lnum = lint.range[3],
        col = lint.range[2], end_col = lint.range[4],
        severity = vim.diagnostic.ERROR,
        message = lint.message
      }
    end, lints)
    vim.diagnostic.set(namespace, buf, diagnostics)
  end
end

local function add_lint_for_node(node, buf, error_type, complete_message)
  local node_text = vim.treesitter.query.get_node_text(node, buf):gsub("\n", " ")
  local error_text = complete_message or error_type .. ": " .. node_text
  local error_range = { node:range() }
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

  if not ok then
    return
  end

  local matches = queries.get_matches(query_buf, "query-linter-queries")

  for _, m in pairs(matches) do
    local error_node = utils.get_at_path(m, "error.node")

    if error_node then
      add_lint_for_node(error_node, query_buf, "Syntax Error")
    end

    local toplevel_node = utils.get_at_path(m, "toplevel-query.node")
    if toplevel_node and query_lang then
      local query_text = vim.treesitter.query.get_node_text(toplevel_node, query_buf)
      local err
      ok, err = pcall(vim.treesitter.parse_query, query_lang, query_text)
      if not ok then
        add_lint_for_node(toplevel_node, query_buf, "Invalid Query", err)
      end
    end

    if parser_info and parser_info.symbols then
      local named_node = utils.get_at_path(m, "named_node.node")
      local anonymous_node = utils.get_at_path(m, "anonymous_node.node")
      local node = named_node or anonymous_node
      if node then
        local node_type = vim.treesitter.query.get_node_text(node, query_buf)

        if anonymous_node then
          node_type = node_type:gsub('"(.*)".*$', "%1"):gsub("\\(.)", "%1")
        end

        local is_named = named_node ~= nil

        local found = vim.tbl_contains(MAGIC_NODE_NAMES, node_type)
          or table_contains(function(t)
            return node_type == t[1] and is_named == t[2]
          end, parser_info.symbols)

        if not found then
          add_lint_for_node(node, query_buf, "Invalid Node Type")
        end
      end

      local field_node = utils.get_at_path(m, "field.node")

      if field_node then
        local field_name = vim.treesitter.query.get_node_text(field_node, query_buf)
        local found = vim.tbl_contains(parser_info.fields, field_name)
        if not found then
          add_lint_for_node(field_node, query_buf, "Invalid Field")
        end
      end
    end
  end

  show_lints(query_buf, M.lints[query_buf])
  return M.lints[query_buf]
end

function M.clear_virtual_text(buf)
  vim.diagnostic.reset(namespace, buf)
end

function M.attach(buf, _)
  M.lints[buf] = {}

  local config = configs.get_module "query_linter"
  M.use_diagnostics = config.use_diagnostics
  M.lint_events = config.lint_events

  vim.api.nvim_create_autocmd(M.lint_events, {
    group = vim.api.nvim_create_augroup("TSPlaygroundLint", {}),
    buffer = buf,
    callback = function()
      require("nvim-treesitter-playground.query_linter").lint(buf)
    end,
    desc = "TSPlayground: lint query",
  })
end

function M.detach(buf)
  M.lints[buf] = nil
  M.clear_virtual_text(buf)
  vim.api.nvim_clear_autocmds { group = "TSPlaygroundLint", buffer = buf, event = M.lint_events }
end

return M
