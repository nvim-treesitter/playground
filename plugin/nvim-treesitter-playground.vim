lua << EOF
require "nvim-treesitter-playground".init()
EOF

highlight default link TSPlaygroundFocus Visual
highlight TSPlaygroundCapture1 ctermfg=Blue guifg=Blue
highlight TSPlaygroundCapture2 ctermfg=LightBlue guifg=LightBlue
highlight TSPlaygroundCapture3 ctermfg=Green guifg=Green
highlight TSPlaygroundCapture4 ctermfg=LightGreen guifg=LightGreen

command! TSPlaygroundToggle lua require "nvim-treesitter-playground.internal".toggle()
