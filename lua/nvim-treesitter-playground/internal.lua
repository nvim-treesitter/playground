local configs = require 'nvim-treesitter.configs'
local printer = require 'nvim-treesitter-playground.printer'
local api = vim.api

local M = {}

M._displays_by_buf = {}

local function setup_buf()
  local buf = api.nvim_create_buf(false, true)

  api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  api.nvim_buf_set_option(buf, 'swapfile', false)
  api.nvim_buf_set_option(buf, 'bufhidden', 'delete')
  api.nvim_buf_set_option(buf, 'buflisted', false)
  api.nvim_buf_set_option(buf, 'filetype', 'tsplayground')

  return buf
end

function M.open(bufnr)
  local bufnr = bufnr or api.nvim_get_current_buf()
  local display_buf = setup_buf()

  M._displays_by_buf[bufnr] = display_buf
  vim.cmd "vsplit"
  vim.cmd(string.format("buffer %d", display_buf))

  api.nvim_win_set_option(0, 'spell', false)
  api.nvim_win_set_option(0, 'number', false)
  api.nvim_win_set_option(0, 'relativenumber', false)
  api.nvim_win_set_option(0, 'cursorline', false)

  M.update(bufnr)
end

function M.update(bufnr)
  local bufnr = bufnr or api.nvim_get_current_buf()
  local display_buf = M._displays_by_buf[bufnr]

  if not display_buf then return end

  local lines = printer.print(bufnr)

  -- TODO: Associate lines with nodes for highlighting

  api.nvim_buf_set_lines(display_buf, 0, -1, false, lines)
end

function M.attach(bufnr, lang)
  local buf = bufnr or api.nvim_get_current_buf()
  local config = configs.get_module 'playground'

  for fn, mapping in pairs(config.keymaps) do
    if mapping then
      local cmd = string.format(":lua require 'nvim-treesitter-playground.internal'.%s()<CR>", fn)
      api.nvim_buf_set_keymap(bufnr, 'n', mapping, cmd, { silent = true })
    end
  end

  api.nvim_buf_attach(buf, true, {
    on_lines = vim.schedule_wrap(function() M.update(buf) end)
  })
end

function M.detach(bufnr)
  -- TODO: Clean up here
end

return M
