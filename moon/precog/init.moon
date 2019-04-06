-- The module has to track state which does actually need to be global, so it
-- does get exported
-- TODO suport the "info" attributes in complete-items
-- TODO suport the "kind" attributes in complete-items, where possible
-- TODO per-source priorities
export precog
-- TODO broad logging?
vimw = require "facade"
inspect = require "vendor.inspect"
utils = require "precog.utils"
table_ = require "earthshine.table"

local *
precog =
  -- Module defaults/initialization
  sources: {}
  sources_for_buffer: {}
  -- Structure: @candidates[source][word] = true
  candidates: {}
  -- Table reference to the most-recent changedata (generated by TextChanged*
  -- events); this is needed to ensure that async results returned are still
  -- relevant
  current_context: nil
  complete_timer: nil
  log_file: io.open "/tmp/precog.log", "w" -- FIXME won't work well with multiple nvim instances
  -- TODO disable buffers when they are destroyed
  buffers_enabled: {}
  -- We store the per-event data here because we don't want to needlessly pass
  -- it back/forth through VimL. Indexed by timer_id, which is already being
  -- passed around :).
  change_data: {}

  -- Module functions
  buffer_enable: (buffer_handle) =>
    return if @buffers_enabled[buffer_handle]

    vimw.b_set buffer_handle, 'precog_enabled', true
    -- We need to hook some vim events to pick up text entry
    -- Could just use <buffer>, as that would work OK in this context, but
    -- explicit is better than implicit, so we'll template in the buffer number
    -- Also, we actually do want the buffer number in the events, so may as
    -- well just pass it directly to them...
    au_setup = [[
      augroup precog
        au! * <buffer=@NR@>
        au InsertEnter <buffer=@NR@> lua precog:handle_buffer_event(@NR@, "InsertEnter")
        au InsertLeave <buffer=@NR@> lua precog:handle_buffer_event(@NR@, "InsertLeave")
        au TextChangedI <buffer=@NR@> lua precog:handle_buffer_event(@NR@, "TextChangedI")
        au TextChangedP <buffer=@NR@> lua precog:handle_buffer_event(@NR@, "TextChangedP")
        au FileType <buffer=@NR@> lua precog:handle_buffer_event(@NR@, "FileType")
        au BufDelete <buffer=@NR@> lua precog:handle_buffer_event(@NR@, "BufDelete")
      augroup END
      ]]
    au_setup = au_setup\gsub "@NR@", buffer_handle
    vimw.exec au_setup

    @buffers_enabled[buffer_handle] = true
    @setup_sources_for_buffer buffer_handle

  buffer_disable: (buffer_handle) =>
    return unless @buffers_enabled[buffer_handle]

    @buffers_enabled[buffer_handle] = nil
    @sources_for_buffer[buffer_handle] = nil

  handle_buffer_event: (buffer_handle, event) =>
    switch event
      when "InsertEnter"
        @reset_predictions!
        -- TODO handle_changed() here? should still clear candidates as may
        -- have swapped buffers? although maybe insertleave is enough to handle
        -- that

      when "InsertLeave"
        @reset_predictions!

      when "TextChangedI"
        @last = event
        @handle_changed buffer_handle

      when "TextChangedP"
        -- Avoid duplicate initial one where TextChangedI and TextChangedP
        -- "overlap"
        if @last == event
          @handle_changed buffer_handle
        else
          @last = event

      when "FileType"
        -- if @buffers_enabled[buffer_handle]
        --   @setup_sources_for_buffer buffer_handle
        nil

      when "BufDelete"
        @buffer_disable buffer_handle

      else
        -- TODO log this?
        print("nak")
    return nil

  handle_changed: (buffer_handle) =>
    -- Data to grab:
    -- buffer number (we have this)
    -- line number, column (getcurpos())
    -- filetype (nvim_get_option option)
    -- filepath (absolute) (expand('%:p'))
    -- string up to cursor, string after cursor (getline(line number), substring it based on column)
    -- b:changedtick? incremented whenever a change is made to the buffer, including an undo
    curpos = vimw.fn 'getcurpos'
    change_data = with {}
      .buffer_handle = buffer_handle
      .line_number = curpos[2]
      .line_count = vim.api.nvim_buf_line_count buffer_handle
      .col = curpos[3]
      .line_content = vim.api.nvim_get_current_line!
      .before_cursor = .line_content\sub 0, .col - 1
      .after_cursor = .line_content\sub .col, #.line_content
      .filetype = vimw.option_get 'filetype'
      .filepath = vimw.fn 'expand', {'%:p'}
      .changedtick = vimw.b_get buffer_handle, 'changedtick'

    -- These may be nil
    last_word, lw_start = utils.get_last_word change_data.before_cursor
    change_data.last_word = last_word
    change_data.start_col = if last_word then lw_start else nil

    -- Schedule change event handling per predictor
    for _name, source in pairs @sources_for_buffer[buffer_handle]
      timer_id = vimw.fn "timer_start", { 0, source.predictor }
      @change_data[timer_id] = change_data

    -- Schedule us to show provided predictions, once the predictors have
    -- finished
    @complete_timer = vimw.fn "timer_start", { 0, "precog#update_predictions" }
    @change_data[@complete_timer] = change_data

    @current_context = change_data

  setup_sources_for_buffer: (buffer_handle) =>
    filetype = vimw.option_get 'filetype'
    sources = if sources_available = @get_sources_for_filetype filetype
      sources_available
    else
      {}
    @sources_for_buffer[buffer_handle] = sources

    for name, source in pairs sources
      if events = source['events']
        @setup_events_for_source events, buffer_handle
      if source_cb = source['new_buffer']
        source_cb = source_cb\gsub "@NR@", buffer_handle
        vim.api.nvim_eval source_cb
      if lua_init = source['lua_init']
        vimw.fn "luaeval", { lua_init, buffer_handle }
      unless @candidates[name]
        @candidates[name] = {}

  -- 'source' structure:
  -- {
  --   blacklist: [ft1, ft2, ..., ftn]
  --   whitelist: [ft1, ft2, ..., ftn]
  --   predictor: some Vim function name
  --   events: {
  --     "BufEnter": "some Vim function name"
  --   }
  -- }
  -- blacklist and whitelist are optional, and if neither is set, then the
  -- source will always be active
  -- events is optional
  get_sources_for_filetype: (filetype) =>
    sources = {}
    for name, source in pairs @sources
      if blacklist = source['blacklist']
        if is_filetype_on_list filetype, blacklist
          continue
      elseif whitelist = source['whitelist']
        if is_filetype_on_list filetype, whitelist
          sources[name] = source
        else
          continue
      else
        sources[name] = source
    return sources

  log: (msg) =>
    if type msg == 'table'
      msg = inspect msg
    @log_file\write msg .. "\n"
    @log_file\flush!

  register_source: (name, source) =>
    @log "Registering source #{name}:\n#{inspect source}"
    @sources[name] = source

  reset_predictions: () =>
    for source, _words in pairs @candidates
      @candidates[source] = {}
    @stop_update!

  update_predictions: (timer_id) =>
    prediction_context = @change_data[timer_id]

    insert_mode = (vimw.fn 'mode') == 'i'
    if insert_mode and prediction_context == @current_context
      prefix_word = (utils.get_last_word prediction_context.before_cursor) or ""

      candidates = @filtered_candidates prefix_word
      table.sort candidates, ((a, b) -> @compare_candidates a, b)
      candidates = @format_candidates candidates
      if #candidates > 0
        start_col = prediction_context.start_col or prediction_context.col
        vimw.fn 'complete', { start_col, candidates }

    @change_data[timer_id] = nil
    @complete_timer = nil

  -- Sort candidates by source-priority, then lexicographically
  compare_candidates: (cand_a, cand_b) =>
    high_source_a = table_.max cand_a.sources, ((a, b) -> @compare_sources a, b)
    high_source_b = table_.max cand_b.sources, ((a, b) -> @compare_sources a, b)
    if @sources[high_source_a].priority == @sources[high_source_b].priority
      return cand_a.word < cand_b.word
    else
      return @compare_sources high_source_a, high_source_b

  compare_sources: (source_a, source_b) =>
    return @sources[source_a].priority > @sources[source_b].priority

  stop_update: () =>
    if @complete_timer
      vimw.fn "timer_stop", { @complete_timer }
      @change_data[@complete_timer] = nil
      @complete_timer = nil

  filtered_candidates: (prefix_word) =>
    -- Filter by using the last word in the current line as a prefix
    -- Also removes outdated candidates (ones with mismatched context
    -- references)
    filtered = {}
    for source, words in pairs @candidates
      for word, context in pairs words
        if context != @current_context
          words[word] = nil
        elseif not prefix_word or (word\sub 1, #prefix_word) == prefix_word
          sources = filtered[word] or {}
          table.insert sources, source
          table.insert filtered, {:word, :sources}
    return filtered

  format_candidates: (candidates) =>
    formatted = {}
    for idx, {:word, :sources} in ipairs candidates
      menu = ""
      for source in *sources
        menu ..= "[#{source}]"
      formatted[idx] = {:word, :menu}
    return formatted

  add_candidates: (source, timer_id, new_candidates) =>
    -- We must throw away old candidates once the startcol has changed
    candidate_context = @change_data[timer_id]
    for item in *new_candidates
      @candidates[source][item] = candidate_context

    -- Update the displayed predictions
    @stop_update!
    @complete_timer = vimw.fn "timer_start", { 0, "precog#update_predictions" }
    @change_data[@complete_timer] = candidate_context

    @change_data[timer_id] = nil

  get_candidates: () =>
    return @candidates

  setup_events_for_source: (events, buffer_handle) =>
    au_setup = "augroup precog\n"
    for event, action in pairs events
      au_setup ..= "au #{event} <buffer=#{buffer_handle}> #{action}\n"
    au_setup ..= "augroup END\n"
    au_setup = au_setup\gsub "@NR@", buffer_handle
    vimw.exec au_setup

is_filetype_on_list = (filetype, list) ->
  for listed_filetype in *list
    filetype == listed_filetype or listed_filetype == '*'
    return true
  return false

return precog
