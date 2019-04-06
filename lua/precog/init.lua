local vimw = require("facade")
local inspect = require('vendor.inspect')
local utils = require('precog.utils')
local is_filetype_on_list
precog = {
  sources_for_buffer = { },
  candidates = { },
  current_context = nil,
  complete_timer = nil,
  log_file = io.open("/tmp/precog.log", "w"),
  buffers_enabled = { },
  change_data = { },
  buffer_enable = function(self, buffer_handle)
    if self.buffers_enabled[buffer_handle] then
      return 
    end
    vimw.b_set(buffer_handle, 'precog_enabled', true)
    local au_setup = [[      augroup precog
        au! * <buffer=@NR@>
        au InsertEnter <buffer=@NR@> lua precog:handle_buffer_event(@NR@, "InsertEnter")
        au InsertLeave <buffer=@NR@> lua precog:handle_buffer_event(@NR@, "InsertLeave")
        au TextChangedI <buffer=@NR@> lua precog:handle_buffer_event(@NR@, "TextChangedI")
        au TextChangedP <buffer=@NR@> lua precog:handle_buffer_event(@NR@, "TextChangedP")
        au FileType <buffer=@NR@> lua precog:handle_buffer_event(@NR@, "FileType")
        au BufDelete <buffer=@NR@> lua precog:handle_buffer_event(@NR@, "BufDelete")
      augroup END
      ]]
    au_setup = au_setup:gsub("@NR@", buffer_handle)
    vimw.exec(au_setup)
    self.buffers_enabled[buffer_handle] = true
    return self:setup_sources_for_buffer(buffer_handle)
  end,
  buffer_disable = function(self, buffer_handle)
    if not (self.buffers_enabled[buffer_handle]) then
      return 
    end
    self.buffers_enabled[buffer_handle] = nil
    self.sources_for_buffer[buffer_handle] = nil
  end,
  handle_buffer_event = function(self, buffer_handle, event)
    local _exp_0 = event
    if "InsertEnter" == _exp_0 then
      self:reset_predictions()
    elseif "InsertLeave" == _exp_0 then
      self:reset_predictions()
    elseif "TextChangedI" == _exp_0 then
      self.last = event
      self:handle_changed(buffer_handle)
    elseif "TextChangedP" == _exp_0 then
      if self.last == event then
        self:handle_changed(buffer_handle)
      else
        self.last = event
      end
    elseif "FileType" == _exp_0 then
      local _ = nil
    elseif "BufDelete" == _exp_0 then
      self:buffer_disable(buffer_handle)
    else
      print("nak")
    end
    return nil
  end,
  handle_changed = function(self, buffer_handle)
    local curpos = vimw.fn('getcurpos')
    local change_data
    do
      local _with_0 = { }
      _with_0.buffer_handle = buffer_handle
      _with_0.line_number = curpos[2]
      _with_0.line_count = vim.api.nvim_buf_line_count(buffer_handle)
      _with_0.col = curpos[3]
      _with_0.line_content = vim.api.nvim_get_current_line()
      _with_0.before_cursor = _with_0.line_content:sub(0, _with_0.col - 1)
      _with_0.after_cursor = _with_0.line_content:sub(_with_0.col, #_with_0.line_content)
      _with_0.filetype = vimw.option_get('filetype')
      _with_0.filepath = vimw.fn('expand', {
        '%:p'
      })
      _with_0.changedtick = vimw.b_get(buffer_handle, 'changedtick')
      change_data = _with_0
    end
    local last_word, lw_start = utils.get_last_word(change_data.before_cursor)
    change_data.last_word = last_word
    if last_word then
      change_data.start_col = lw_start
    else
      change_data.start_col = nil
    end
    for _name, source in pairs(self.sources_for_buffer[buffer_handle]) do
      local timer_id = vimw.fn("timer_start", {
        0,
        source.predictor
      })
      self.change_data[timer_id] = change_data
    end
    self.complete_timer = vimw.fn("timer_start", {
      0,
      "precog#update_predictions"
    })
    self.change_data[self.complete_timer] = change_data
    self.current_context = change_data
  end,
  setup_sources_for_buffer = function(self, buffer_handle)
    local filetype = vimw.option_get('filetype')
    local sources
    do
      local sources_available = self:get_sources_for_filetype(filetype)
      if sources_available then
        sources = sources_available
      else
        sources = { }
      end
    end
    self.sources_for_buffer[buffer_handle] = sources
    for name, source in pairs(sources) do
      do
        local events = source['events']
        if events then
          self:setup_events_for_source(events, buffer_handle)
        end
      end
      do
        local source_cb = source['new_buffer']
        if source_cb then
          source_cb = source_cb:gsub("@NR@", buffer_handle)
          vim.api.nvim_eval(source_cb)
        end
      end
      do
        local lua_init = source['lua_init']
        if lua_init then
          vimw.fn("luaeval", {
            lua_init,
            buffer_handle
          })
        end
      end
      if not (self.candidates[name]) then
        self.candidates[name] = { }
      end
    end
  end,
  get_sources_for_filetype = function(self, filetype)
    local available_sources = vimw.g_get('precog_sources', { })
    local sources = { }
    for name, source in pairs(available_sources) do
      local _continue_0 = false
      repeat
        if type(name) ~= "string" then
          _continue_0 = true
          break
        end
        do
          local blacklist = source['blacklist']
          if blacklist then
            if is_filetype_on_list(filetype, blacklist) then
              _continue_0 = true
              break
            end
          end
        end
        do
          local whitelist = source['whitelist']
          if whitelist then
            if is_filetype_on_list(filetype, whitelist) then
              sources[name] = source
            else
              _continue_0 = true
              break
            end
          else
            sources[name] = source
          end
        end
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
    return sources
  end,
  log = function(self, msg)
    if type(msg == 'table') then
      msg = inspect(msg)
    end
    self.log_file:write(msg .. "\n")
    return self.log_file:flush()
  end,
  register_source = function(self, name, source)
    local sources = vimw.g_get('precog_sources')
    sources[name] = source
    self:log("Registering source " .. tostring(name) .. ":\n" .. tostring(inspect(source)))
    return vimw.g_set('precog_sources', sources)
  end,
  reset_predictions = function(self)
    for source, _words in pairs(self.candidates) do
      self.candidates[source] = { }
    end
    return self:stop_update()
  end,
  update_predictions = function(self, timer_id)
    local prediction_context = self.change_data[timer_id]
    local insert_mode = (vimw.fn('mode')) == 'i'
    if insert_mode and prediction_context == self.current_context then
      local prefix_word = (utils.get_last_word(prediction_context.before_cursor)) or ""
      local candidates = self:filtered_candidates(prefix_word)
      if #candidates > 0 then
        local start_col = prediction_context.start_col or prediction_context.col
        vimw.fn('complete', {
          start_col,
          candidates
        })
      end
    end
    self.change_data[timer_id] = nil
    self.complete_timer = nil
  end,
  stop_update = function(self)
    if self.complete_timer then
      vimw.fn("timer_stop", {
        self.complete_timer
      })
      self.change_data[self.complete_timer] = nil
      self.complete_timer = nil
    end
  end,
  filtered_candidates = function(self, prefix_word)
    local filtered = { }
    for source, words in pairs(self.candidates) do
      for word, context in pairs(words) do
        if context ~= self.current_context then
          words[word] = nil
        elseif not prefix_word or (word:sub(1, #prefix_word)) == prefix_word then
          local menu = filtered[word] or ""
          menu = menu .. "[" .. tostring(source) .. "]"
          filtered[word] = menu
        end
      end
    end
    local _accum_0 = { }
    local _len_0 = 1
    for word, menu in pairs(filtered) do
      _accum_0[_len_0] = {
        word = word,
        menu = menu
      }
      _len_0 = _len_0 + 1
    end
    return _accum_0
  end,
  add_candidates = function(self, source, timer_id, new_candidates)
    local candidate_context = self.change_data[timer_id]
    for _index_0 = 1, #new_candidates do
      local item = new_candidates[_index_0]
      self.candidates[source][item] = candidate_context
    end
    self:stop_update()
    self.complete_timer = vimw.fn("timer_start", {
      0,
      "precog#update_predictions"
    })
    self.change_data[self.complete_timer] = candidate_context
    self.change_data[timer_id] = nil
  end,
  get_candidates = function(self)
    return self.candidates
  end,
  setup_events_for_source = function(self, events, buffer_handle)
    local au_setup = "augroup precog\n"
    for event, action in pairs(events) do
      au_setup = au_setup .. "au " .. tostring(event) .. " <buffer=" .. tostring(buffer_handle) .. "> " .. tostring(action) .. "\n"
    end
    au_setup = au_setup .. "augroup END\n"
    au_setup = au_setup:gsub("@NR@", buffer_handle)
    return vimw.exec(au_setup)
  end
}
is_filetype_on_list = function(filetype, list)
  for _index_0 = 1, #list do
    local listed_filetype = list[_index_0]
    local _ = filetype == listed_filetype or listed_filetype == '*'
    return true
  end
  return false
end
return precog
