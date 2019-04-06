-- TODO case-sensitivity?
-- TODO allow for deleting words?
-- TODO find a C or Rust regex/Unicode library with support for patterns using
-- TODO use the '[ and '] marks to range-find changed text for minimal updates
-- Unicode character classes, as well as string iteration and comparison by
-- grapheme cluster, then use that to reimplement this via Lua bindings
export precog
require 'precog'
table_ = require "earthshine.table"
inspect = require 'vendor.inspect'
MADFA = require 'earthshine.madfa'
utils = require 'precog.utils'

local *

precog.buffer =
  -- Module initialization
  source_name: "buffer"
  words: MADFA!
  last_line_count: nil
  last_line_no: nil

  register: () =>
    precog\log "buffer:register() called!"
    precog\register_source @source_name,
      predictor: "precog#sources#buffer#predictor"
      -- events:
      --   InsertEnter: "lua precog.buffer:track_changes(@NR@)"
      --   InsertLeave: "lua precog.buffer:stop_tracking_changes(@NR@)"
      lua_init: "precog.buffer:full_update(_A)"
      priority: 15

  predictor: (timer_id) =>
    change_data = precog.change_data[timer_id]

    -- precog\log "buffer:predictor() called, change_data:\n#{inspect change_data}"

    -- Handle incremental modifications to the buffer.
    -- In future, may want to leverage RPC events once they're available to
    -- the Lua API (e.g. nvim_buf_lines_event).
    if @last_line_count and @last_line_count < change_data.line_count
      -- We need to add some number of preceding or following lines. Note:
      -- line indexing in nvim_buf_get_lines is, inexplicably, 0-based, so we
      -- need to account for it being off-by-1.
      new_line_count = change_data.line_count - @last_line_count
      local start_line_no, end_line_no
      if change_data.line_number <= @last_line_no
        -- The new lines were added after the current line (e.g. with `P`)
        start_line_no = change_data.line_number - 1
        end_line_no = start_line_no + new_line_count
      else
        -- The new lines were added before the current line
        end_line_no = change_data.line_number -- nvim_buf_get_lines is end-exclusive, so no -1 here
        start_line_no = math.max(end_line_no - new_line_count - 1, 0)
      new_lines = vim.api.nvim_buf_get_lines change_data.buffer_handle,
        start_line_no, end_line_no, false
      for line in *new_lines
        @incremental_update line

    if change_data.last_word
      -- Add any words in the current line prior to the start of the last word
      -- (as we may still be typing it)
      @incremental_update change_data.line_content\sub 1, change_data.start_col - 1

      -- Using the last word as a prefix, see if there are any words in the word
      -- set with that prefix.
      candidates = @words\subset change_data.last_word

      -- Actually submit our prediction candidates to precog
      precog\add_candidates @source_name, timer_id, candidates

    @last_line_count = change_data.line_count
    @last_line_no = change_data.line_number

  incremental_update: (line) =>
    -- TODO needs to be unicode-aware at some point...
    for word in line\gmatch utils.word_pattern
      @words\add_word word if #word >= 5

  full_update: (buffer_handle) =>
    buffers_enabled = table_.keys precog.buffers_enabled
    if buffers_enabled[buffer_handle]
      -- TODO cache based on nvim_buf_get_changedtick
      -- Split contents by line, then into words
      lines = vim.api.nvim_buf_get_lines buffer_handle, 0, -1, false
      for line in *lines
        @incremental_update line
