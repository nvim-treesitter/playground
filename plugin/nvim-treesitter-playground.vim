lua << EOF
require "nvim-treesitter-playground".init()
EOF

highlight default link TSPlaygroundFocus Visual
highlight default link TSQueryLinterError Error
highlight default link TSPlaygroundLang String

command! TSPlaygroundToggle lua require "nvim-treesitter-playground.internal".toggle()
