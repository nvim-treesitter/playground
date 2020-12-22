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
    unnamed = false, -- Whether to show unnamed nodes by default
  }
}
```

## Usage

The tree can be toggled using the command `:TSPlaygroundToggle`.

### Keybindings

- `R`: Refreshes the playground view when focused or reloads the query when the query editor is focused.
- `o`: Toggles the query editor when the playground is focused
- `u`: Toggles display of unnamed nodes
- `<cr>`: Go to current node in code buffer

## Query Linter

The playground can lint query files for you. For that, you need to activate the `query_linter` module:

```lua
require "nvim-treesitter.configs".setup {
  query_linter = {
    enable = true,
    use_virtual_text = true,
    lint_events = {"BufWrite", "CursorHold"},
  },
}
```

![image](https://user-images.githubusercontent.com/7189118/101246661-06089a00-3715-11eb-9c57-6d6439defbf8.png)

# Roadmap
  - [ ] Add interactive query highlighting
