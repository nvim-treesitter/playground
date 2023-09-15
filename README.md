# Neovim Treesitter Playground

View treesitter information directly in Neovim!

![demo](https://user-images.githubusercontent.com/2361214/202389106-244ac890-9442-4759-9b2c-4fe3c247dfbc.gif)

## Deprecation notice

This plugin is **deprecated** since the functionality is included in Neovim: Use

- `:Inspect` to show the highlight groups under the cursor
- `:InspectTree` to show the parsed syntax tree ("TSPlayground")
- `:EditQuery` to open the Live Query Editor (Nvim 0.10+)

## Requirements
  - Neovim [nightly](https://github.com/neovim/neovim#install-from-source)
  - [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) plugin (with the `query` grammar installed)

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
    persist_queries = false, -- Whether the query persists across vim sessions
    keybindings = {
      toggle_query_editor = 'o',
      toggle_hl_groups = 'i',
      toggle_injected_languages = 't',
      toggle_anonymous_nodes = 'a',
      toggle_language_display = 'I',
      focus_language = 'f',
      unfocus_language = 'F',
      update = 'R',
      goto_node = '<cr>',
      show_help = '?',
    },
  }
}
```

## Usage

The tree can be toggled using the command `:TSPlaygroundToggle`.

### Keybindings

- `R`: Refreshes the playground view when focused or reloads the query when the query editor is focused.
- `o`: Toggles the query editor when the playground is focused.
- `a`: Toggles visibility of anonymous nodes.
- `i`: Toggles visibility of highlight groups.
- `I`: Toggles visibility of the language the node belongs to.
- `t`: Toggles visibility of injected languages.
- `f`: Focuses the language tree under the cursor in the playground. The query editor will now be using the focused language.
- `F`: Unfocuses the currently focused language.
- `<cr>`: Go to current node in code buffer

## Query Editor

Press `o` to show the query editor.
Write your query like `(node) @capture`,
put the cursor under the capture to highlight the matches.

## Completions

When you are on a `query` buffer, you can get a list of suggestions with
<kbd>Ctrl-X Ctrl-O</kbd>. See `:h 'omnifunc'`.

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

*Note: Query linter assumes certain directory structure to identify which language queries belong to. It expect query files to be under `./queries/<language_name>`*

![image](https://user-images.githubusercontent.com/7189118/101246661-06089a00-3715-11eb-9c57-6d6439defbf8.png)

## Show treesitter and syntax highlight groups under the cursor 

The playground comes with `:TSHighlightCapturesUnderCursor` that shows any treesitter or syntax highlight groups under the cursor.

<img src="https://user-images.githubusercontent.com/292349/119982982-6665ef00-bf74-11eb-93d5-9b214928c3a9.png" width="450">

<img src="https://user-images.githubusercontent.com/292349/119983093-8c8b8f00-bf74-11eb-9fa2-3670a8253fbd.png" width="450">

## Show treesitter node under the cursor

If you only wish to view information about the node your cursor is currently on (without having to open up the full tree), you can use `:TSNodeUnderCursor` instead.
A floating window containing information about the parser, node name and row/col ranges will be shown.

<img src="https://user-images.githubusercontent.com/30731072/210166267-038c529b-f265-4439-8ed8-807b745cf026.png" width="450">
