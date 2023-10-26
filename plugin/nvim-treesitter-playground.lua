-- setup playground module
require("nvim-treesitter-playground").init()
local api = vim.api

-- define highlights
local highlights = {
  TSPlaygroundFocus = { link = "Visual", default = true },
  TSQueryLinterError = { link = "Error", default = true },
  TSPlaygroundLang = { link = "String", default = true },
}
for k, v in pairs(highlights) do
  api.nvim_set_hl(0, k, v)
end

-- define commands
api.nvim_create_user_command("TSPlaygroundToggle", function()
  require("nvim-treesitter-playground.internal").toggle()
end, {})
api.nvim_create_user_command("TSNodeUnderCursor", function()
  require("nvim-treesitter-playground.hl-info").show_ts_node()
end, {})
---@deprecated
api.nvim_create_user_command("TSCaptureUnderCursor", function()
  vim.notify("TSCaptureUnderCursor was removed. Use Neovim's built-in `:Inspect` instead!", vim.log.levels.ERROR)
end, {})
---@deprecated
api.nvim_create_user_command("TSHighlightCapturesUnderCursor", function()
  vim.notify(
    "TSHighlightCapturesUnderCursor was removed. Use Neovim's built-in `:Inspect` instead!",
    vim.log.levels.ERROR
  )
end, {})
