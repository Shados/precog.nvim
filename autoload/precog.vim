function! precog#buffer_enable() abort
  " Ensure the 'precog' global is available and initialized
  lua require('precog')
  " Set up the event hooks for the buffer
  call luaeval('precog:buffer_enable(_A)', bufnr('%'))
endfunction

function! precog#update_predictions(timer_id) abort
  call luaeval('precog:update_predictions(_A)', a:timer_id)
endfunction
