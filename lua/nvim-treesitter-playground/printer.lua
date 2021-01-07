local parsers = require 'nvim-treesitter.parsers'
local api = vim.api

local M = {}

local function print_tree(root, unnamed, results, indent)
  local results = results or { lines = {}, nodes = {} }
  local indentation = indent or ""

  for node, field in root:iter_children() do
    if node:named() or unnamed then
      local name = node:type()
      if not node:named() then
        name = '"' .. name .. '"'
        -- quote any possible newlines (newlines cause errors in nvim_buf_set_lines)
        name = name:gsub('\n', '\\n')
      end

      local line
      if field then
        line = string.format("%s%s: %s [%d, %d] - [%d, %d]",
          indentation, field, name, node:range())
      else
        line = string.format("%s%s [%d, %d] - [%d, %d]",
          indentation, name, node:range())
      end

      table.insert(results.lines, line)
      table.insert(results.nodes, node)

      print_tree(node, unnamed, results, indentation .. "  ")
    end
  end

  return results
end

function M.print(bufnr, lang, unnamed)
  local bufnr = bufnr or api.nvim_get_current_buf()
  local parser = parsers.get_parser(bufnr, lang)

  if not parser then return end

  return print_tree(parser:parse()[1]:root(), unnamed)
end

local treesitter_namespace = api.nvim_get_namespaces().treesitter_hl
local virt_text_id = api.nvim_create_namespace('TSPlaygroundHlGroups')

local function get_extmarks(bufnr, start, end_)
  return api.nvim_buf_get_extmarks(bufnr, treesitter_namespace, start, end_, { details = true })
end

function M.print_hl_groups(bufnr, display_bufnr, lang)
  local bufnr = bufnr or api.nvim_get_current_buf()
  local parser = parsers.get_parser(bufnr, lang)

  if not parser then return end

  local i = 0
  local function iter(root)
    for node, _ in root:iter_children() do
      if node:named() then
        local start_row, start_col, end_row, end_col = node:range()
        local extmarks = get_extmarks(bufnr, {start_row, start_col}, {end_row, end_col})

        if #extmarks > 0 then
          local groups = {}

          for idx, ext in ipairs(extmarks) do
            local infos = ext[4]
            local hl_group = infos.hl_group
            local str = hl_group.." / "
            if idx == #extmarks then
              str = str:sub(0, -3)
            end
            table.insert(groups, {str, hl_group})
          end
          api.nvim_buf_set_virtual_text(display_bufnr, virt_text_id, i, groups, {})
        end

        i = i + 1
        iter(node)
      end
    end
  end

  iter(parser:parse()[1]:root())
end

function M.remove_hl_groups(bufnr)
  api.nvim_buf_clear_namespace(bufnr, virt_text_id, 0, -1)
end

return M
