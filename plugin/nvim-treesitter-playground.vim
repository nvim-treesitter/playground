lua << EOF
require "nvim-treesitter-playground".init()
EOF

highlight default link TSPlaygroundFocus Visual

command! TSPlaygroundToggle lua require "nvim-treesitter-playground.internal".toggle()
