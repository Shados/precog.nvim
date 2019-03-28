" TODO check for nvim support, error out otherwise

" Setup mappings
inoremap <expr><silent> <Plug>c \<C-r>=precog#complete()\<CR>

" Initialize Lua side of the plugin
lua << EOF
local setup = require("precog.setup")
setup.start()
local buffer = require("precog.buffer")
precog.buffer:register()
local path = require("precog.path")
precog.path:register()
EOF
