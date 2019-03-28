function! precog#sources#path#predictor(timer_id) abort
  call luaeval('precog.path:predictor(_A)', a:timer_id)
endfunction

function! precog#sources#path#ls_callback(job_id, data, event) dict
  if a:event ==# 'stdout'
    call luaeval('precog.path:ls_callback(_A[1], _A[2], _A[3])', [a:job_id, self, a:data])
  endif
endfunction
