function! precog#buffer_enable() abort
  " Ensure the 'precog' global is available and initialized
  lua require('precog')
  " Set up the event hooks for the buffer
  call luaeval('precog:buffer_enable(_A)', bufnr('%'))
endfunction

function! precog#update_predictions(timer_id) abort
  call luaeval('precog:update_predictions(_A)', a:timer_id)
endfunction

" VimL wrapper for the convenience of possible pure-VimL sources
function! precog#register_source(name, opts) abort
  lua require('precog')
  call luaeval('precog:register_source(_A[1], _A[2])', [a:name, a:opts])
endfunction
