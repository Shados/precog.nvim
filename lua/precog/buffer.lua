require('precog')
local table_ = require("earthshine.table")
local inspect = require('vendor.inspect')
local MADFA = require('earthshine.madfa')
local utils = require('precog.utils')
precog.buffer = {
  source_name = "buffer",
  words = MADFA(),
  last_line_count = nil,
  last_line_no = nil,
  register = function(self)
    precog:log("buffer:register() called!")
    return precog:register_source(self.source_name, {
      predictor = "precog#sources#buffer#predictor",
      lua_init = "precog.buffer:full_update(_A)",
      priority = 15
    })
  end,
  predictor = function(self, timer_id)
    local change_data = precog.change_data[timer_id]
    if self.last_line_count and self.last_line_count < change_data.line_count then
      local new_line_count = change_data.line_count - self.last_line_count
      local start_line_no, end_line_no
      if change_data.line_number <= self.last_line_no then
        start_line_no = change_data.line_number - 1
        end_line_no = start_line_no + new_line_count
      else
        end_line_no = change_data.line_number
        start_line_no = math.max(end_line_no - new_line_count - 1, 0)
      end
      local new_lines = vim.api.nvim_buf_get_lines(change_data.buffer_handle, start_line_no, end_line_no, false)
      for _index_0 = 1, #new_lines do
        local line = new_lines[_index_0]
        self:incremental_update(line)
      end
    end
    if change_data.last_word then
      self:incremental_update(change_data.line_content:sub(1, change_data.start_col - 1))
      local candidates = self.words:subset(change_data.last_word)
      precog:add_candidates(self.source_name, timer_id, candidates)
    end
    self.last_line_count = change_data.line_count
    self.last_line_no = change_data.line_number
  end,
  incremental_update = function(self, line)
    for word in line:gmatch(utils.word_pattern) do
      if #word >= 5 then
        self.words:add_word(word)
      end
    end
  end,
  full_update = function(self, buffer_handle)
    local buffers_enabled = table_.keys(precog.buffers_enabled)
    if buffers_enabled[buffer_handle] then
      local lines = vim.api.nvim_buf_get_lines(buffer_handle, 0, -1, false)
      for _index_0 = 1, #lines do
        local line = lines[_index_0]
        self:incremental_update(line)
      end
    end
  end
}
