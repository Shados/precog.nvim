local vimw = require("facade")
local start
start = function()
  if vimw.g_exists('precog_initialized') then
    return nil
  end
  vimw.g_defaults({
    precog_enable_globally = true,
    precog_autopredict = true,
    precog_fuzzy_prediction = false,
    precog_dedupe_results = false,
    precog_sources = vimw.empty_dict(),
    precog_filetype_blacklist = vimw.empty_dict()
  })
  vimw.exec([[    augroup precog_filetype_enable
      au!
      au BufEnter * if has_key(b:, "precog_enabled") == 0 && get(g:precog_filetype_blacklist, &filetype) == 0 | call precog#buffer_enable() | endif
    augroup END
    ]])
  vimw.g_set('precog_initialized', true)
  return vimw.option_set('completeopt', 'menuone,preview,noselect')
end
return {
  start = start
}
