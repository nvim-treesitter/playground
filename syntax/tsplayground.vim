if exists('b:current_syntax')
  finish
endif

syn match nodeType "[a-zA-Z_]\+"
syn match nodeNumber "\d\+"
syn match nodeOp "[,\-\)]\+"
syn match nodeTag "\k\+:"
syn match nodeAnonymous "\".\+\""

hi def link nodeType Identifier
hi def link nodeNumber Number
hi def link nodeOp Operator
hi def link nodeTag Tag
hi def link nodeAnonymous String

let b:current_syntax = 'tsplayground'
