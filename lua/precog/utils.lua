local Utils
Utils = {
  word_pattern = "([%w_-]+)",
  get_last_match = function(pattern, str)
    local last_word, lw_start, lw_end, init = nil, 0, 0, 0
    while lw_start and lw_end < #str do
      init = lw_end + 1
      lw_start, lw_end, last_word = str:find(pattern, init)
    end
    return last_word, lw_start, lw_end
  end,
  get_last_word = function(str)
    return Utils.get_last_match(Utils.word_pattern, str)
  end
}
return Utils
