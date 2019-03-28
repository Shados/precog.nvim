-- This is in its own module to avoid having to require() the main
-- functionality in the case that someone is editing a filetype for which they
-- have precog disabled
vimw = require "facade"

start = ->
  -- Skip if already initialized
  if vimw.g_exists 'precog_initialized'
    return nil

  -- Initialize unset configuration options with defaults
  vimw.g_defaults
    precog_enable_globally: true
    precog_autopredict: true
    -- precog_prediction_delay_ms: 100
    precog_fuzzy_prediction: false
    precog_dedupe_results: false
    precog_sources: vimw.empty_dict!
    precog_filetype_blacklist: vimw.empty_dict!

  -- Set up auto-enabling of predictions for buffers of any filetype not in the blacklist
  vimw.exec [[
    augroup precog_filetype_enable
      au!
      au BufEnter * if has_key(b:, "precog_enabled") == 0 && get(g:precog_filetype_blacklist, &filetype) == 0 | call precog#buffer_enable() | endif
    augroup END
    ]]
  vimw.g_set 'precog_initialized', true
  vimw.option_set 'completeopt', 'menuone,preview,noselect'

{ :start }
