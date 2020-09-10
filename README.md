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

It's also recommended that you install the `query` parser for query editor highlighting. Run this after installing the above plugins.

```vim
:TSInstall query
```

The configuration is like any other nvim-treesitter module.

```lua
require "nvim-treesitter.configs".setup {
  playground = {
    enable = true,
    disable = {},
    updatetime = 25, -- Debounced time for highlighting nodes in the playground from source code
    persist_queries = false -- Whether the query persists across vim sessions
  }
}
```

## Usage

The tree can be toggled using the command `:TSPlaygroundToggle`.

### Keybindings

- 'R': Refreshes the playground view when focused or reloads the query when the query editor is focused.
- 'o': Toggles the query editor when the playground is focused
- '<cr>': Go to current node in code buffer

# Roadmap
  - [ ] Add interactive query highlighting
