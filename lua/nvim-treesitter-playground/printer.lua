local parsers = require "nvim-treesitter.parsers"
local utils = require "nvim-treesitter-playground.utils"
local api = vim.api

local M = {}
local treesitter_namespace = api.nvim_get_namespaces()["treesitter/highlighter"]
local virt_text_id = api.nvim_create_namespace "TSPlaygroundHlGroups"
local lang_virt_text_id = api.nvim_create_namespace "TSPlaygroundLangGroups"

local function get_extmarks(bufnr, start, end_)
  return api.nvim_buf_get_extmarks(bufnr, treesitter_namespace, start, end_, { details = true })
end

local function get_hl_group_for_node(bufnr, node)
  local start_row, start_col, end_row, end_col = node:range()
  local extmarks = get_extmarks(bufnr, { start_row, start_col }, { end_row, end_col })
  local groups = {}

  if #extmarks > 0 then
    for _, ext in ipairs(extmarks) do
      table.insert(groups, ext[4].hl_group)
    end
  end

  return groups
end

local function flatten_node(root, results, level, language_tree, options)
  level = level or 0
  results = results or {}

  for node, field in root:iter_children() do
    if node:named() or options.include_anonymous_nodes then
      local node_entry = {
        level = level,
        node = node,
        field = field,
        language_tree = language_tree,
        hl_groups = options.include_hl_groups and options.bufnr and get_hl_group_for_node(options.bufnr, node) or {},
      }

      table.insert(results, node_entry)

      flatten_node(node, results, level + 1, language_tree, options)
    end
  end

  return results
end

local function flatten_lang_tree(lang_tree, results, options)
  results = results or {}

  for _, tree in ipairs(lang_tree:trees()) do
    local root = tree:root()
    local head_entry = nil
    local head_entry_index = nil

    for i, node_entry in ipairs(results) do
      local is_contained = utils.node_contains(node_entry.node, { root:range() })

      if is_contained then
        if not head_entry then
          head_entry = node_entry
          head_entry_index = i
        else
          if node_entry.level >= head_entry.level then
            head_entry = node_entry
            head_entry_index = i
          else
            -- If entry contains the root tree but is less specific, then we
            -- can exit the loop
            break
          end
        end
      end
    end

    local insert_index = head_entry_index and head_entry_index or #results
    local level = head_entry and head_entry.level + 1 or nil

    local flattened_root = flatten_node(root, nil, level, lang_tree, options)
    local i = insert_index + 1

    -- Insert new items into the table at the correct positions
    for _, entry in ipairs(flattened_root) do
      table.insert(results, i, entry)
      i = i + 1
    end
  end

  if not options.suppress_injected_languages then
    for _, child in pairs(lang_tree:children()) do
      flatten_lang_tree(child, results, options)
    end
  end

  return results
end

function M.process(bufnr, lang_tree, options)
  bufnr = bufnr or api.nvim_get_current_buf()
  options = options or {}
  lang_tree = lang_tree or parsers.get_parser(bufnr)
  options.bufnr = options.bufnr or bufnr

  if not lang_tree then
    return {}
  end

  return flatten_lang_tree(lang_tree, nil, options)
end

function M.print_entry(node_entry)
  local line
  local indent = string.rep("  ", node_entry.level)
  local node = node_entry.node
  local field = node_entry.field
  local node_name = node:type()

  if not node:named() then
    node_name = string.format([["%s"]], node_name)
    node_name = string.gsub(node_name, "\n", "\\n")
  end

  if field then
    line = string.format("%s%s: %s [%d, %d] - [%d, %d]", indent, field, node_name, node:range())
  else
    line = string.format("%s%s [%d, %d] - [%d, %d]", indent, node_name, node:range())
  end

  return line
end

function M.print_entries(node_entries)
  local results = {}

  for _, entry in ipairs(node_entries) do
    table.insert(results, M.print_entry(entry))
  end

  return results
end

function M.print_hl_groups(bufnr, node_entries)
  for i, node_entry in ipairs(node_entries) do
    local groups = {}

    for j, hl_group in ipairs(node_entry.hl_groups) do
      local str = hl_group .. " / "

      if j == #hl_group then
        str = string.sub(str, 0, -3)
      end

      table.insert(groups, { str, hl_group })
    end

    api.nvim_buf_set_virtual_text(bufnr, virt_text_id, i, groups, {})
  end
end

function M.print_language(bufnr, node_entries)
  for i, node_entry in ipairs(node_entries) do
    api.nvim_buf_set_virtual_text(bufnr, lang_virt_text_id, i - 1, { { node_entry.language_tree:lang() } }, {})
  end
end

function M.remove_hl_groups(bufnr)
  api.nvim_buf_clear_namespace(bufnr, virt_text_id, 0, -1)
end

function M.remove_language(bufnr)
  api.nvim_buf_clear_namespace(bufnr, lang_virt_text_id, 0, -1)
end

return M
