local *
Utils =
  word_pattern: "([%w_-]+)"

  get_last_match: (pattern, str) ->
    last_word, lw_start, lw_end, init = nil, 0, 0, 0
    while lw_start and lw_end < #str
      init = lw_end + 1
      lw_start, lw_end, last_word = str\find pattern, init
    return last_word, lw_start, lw_end

  get_last_word: (str) ->
    Utils.get_last_match Utils.word_pattern, str

return Utils
