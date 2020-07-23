if exists('b:current_syntax')
  finish
endif

syn match nodeType "[a-zA-Z_]\+"
syn match nodeNumber "\d\+"
syn match nodeOp "[,\-\)]\+"

hi def link nodeType Identifier
hi def link nodeNumber Number
hi def link nodeOp Operator

let b:current_syntax = 'tsplayground'
