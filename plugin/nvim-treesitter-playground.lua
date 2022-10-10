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
end, { bar = true })
api.nvim_create_user_command("TSNodeUnderCursor", function()
  require("nvim-treesitter-playground.hl-info").show_ts_node()
end, { bar = true })
api.nvim_create_user_command("TSCaptureUnderCursor", function()
  require("nvim-treesitter-playground.hl-info").show_hl_captures()
end, { bar = true })
---@deprecated
api.nvim_create_user_command("TSHighlightCapturesUnderCursor", function()
  require("nvim-treesitter-playground.hl-info").show_hl_captures()
end, { bar = true })
