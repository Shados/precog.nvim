function! precog#sources#buffer#predictor(timer_id) abort
  call luaeval('precog.buffer:predictor(_A)', a:timer_id)
endfunction

" For debugging purposes
function! precog#sources#buffer#get_word_set()
  return luaeval('precog.buffer:get_word_set()')
endfunction
