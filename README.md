# Neovim Treesitter Playground

View treesitter information directly in Neovim!

![nvim-treesitter-playground](demo.gif)

## Requirements
  - Neovim [nightly](https://github.com/neovim/neovim#install-from-source)
  - [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) plugin

## Setup

Install the plugin (vim-plug shown):

```vim
Plug 'nvim-treesitter/nvim-treesitter'
Plug 'nvim-treesitter/playground'
```

The configuration is like any other nvim-treesitter module.

```lua
require "nvim-treesitter.configs".setup {
  playground = {
    enable = true,
    disable = {},
    keymaps = {
      open = 'gtd' -- Opens the playground for current buffer (if applicable)
    },
    updatetime = 25 -- Debounced time for highlighting nodes in the playground from source code
  }
}
```

# Roadmap
  - [ ] Add interactive query highlighting
