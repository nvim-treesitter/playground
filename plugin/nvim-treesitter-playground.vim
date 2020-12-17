lua << EOF
require "nvim-treesitter-playground".init()
EOF

highlight default link TSPlaygroundFocus Visual
highlight default link TSQueryLinterError Error

command! TSPlaygroundToggle lua require "nvim-treesitter-playground.internal".toggle()
