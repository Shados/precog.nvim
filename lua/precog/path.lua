require('precog')
require('earthshine.string')
local vimw = require('facade')
local utils = require('precog.utils')
local p = require('earthshine.path')
local inspect = require('inspect')
local map_raw_to_escaped, map_escaped_to_raw
precog.path = {
  source_name = "path",
  valid_quotes = {
    ["'"] = true,
    ["\""] = true,
    ["`"] = true
  },
  register = function(self)
    precog:log("path:register() called")
    return precog:register_source(self.source_name, {
      predictor = "precog#sources#path#predictor",
      priority = 5
    })
  end,
  predictor = function(self, timer_id)
    local change_data = precog.change_data[timer_id]
    local line_content, before_cursor, start_col, col, filepath
    line_content, before_cursor, start_col, col, filepath = change_data.line_content, change_data.before_cursor, change_data.start_col, change_data.col, change_data.filepath
    local path, quoted
    local after_cursor = line_content:at(col)
    if self.valid_quotes[after_cursor] then
      local quote = after_cursor
      path = self:find_inner_path(before_cursor, quote)
    end
    if not (path) then
      path = self:find_unquoted_path(before_cursor)
      quoted = false
    else
      quoted = true
    end
    local parent_dir_path, file_prefix, ends_with_dir = self:get_path_properties(path, filepath)
    return self:schedule_ls_job(timer_id, parent_dir_path, file_prefix, ends_with_dir, not quoted)
  end,
  get_path_properties = function(self, path, filepath)
    local dir_path
    if p.is_absolute(path) then
      dir_path = "/"
    else
      dir_path = p.parse_dir(filepath)
    end
    if (dir_path:at(#dir_path)) ~= "/" then
      dir_path = dir_path .. "/"
    end
    local path_elements = { }
    for element in p.iterate(path) do
      table.insert(path_elements, element)
    end
    local ends_with_dir = #path == 0 or (path:at(#path)) == '/'
    local file_prefix
    if not (ends_with_dir) then
      file_prefix = path_elements[#path_elements]
    else
      file_prefix = nil
    end
    local loop_end
    if ends_with_dir then
      loop_end = #path_elements
    else
      loop_end = #path_elements - 1
    end
    for i = 1, loop_end do
      local element = path_elements[i]
      dir_path = dir_path .. (element .. "/")
    end
    return dir_path, file_prefix, ends_with_dir
  end,
  filter_children = function(self, children, file_prefix, ends_with_dir, should_escape)
    local matches = { }
    for _index_0 = 1, #children do
      local _continue_0 = false
      repeat
        local filename = children[_index_0]
        if filename == "." or filename == ".." or filename == "" then
          _continue_0 = true
          break
        end
        if should_escape then
          filename = self:escape_filename(filename)
        end
        if ends_with_dir then
          table.insert(matches, filename)
        elseif (filename:sub(1, #file_prefix)) == file_prefix then
          table.insert(matches, filename)
        end
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
    return matches
  end,
  path_pattern = "([^%z]*)",
  find_inner_path = function(self, str, quote)
    local last_escape, last_quote
    for index = 1, #str do
      local char = str:at(index)
      if char == "\\" then
        last_escape = index
      elseif char == quote and last_escape ~= index - 1 then
        last_quote = index
      end
    end
    local path_start
    if last_quote then
      path_start = last_quote + 1
    else
      path_start = nil
    end
    if path_start then
      local inner_string = str:sub(path_start, #str)
      if inner_string:match(self.path_pattern) then
        return inner_string
      end
    end
    return nil
  end,
  find_unquoted_path = function(self, str)
    str = utils.get_last_match(self.path_pattern, str)
    if str then
      return str:gsub("\\.", function(s)
        return self:unescape_chars(s)
      end)
    else
      return ""
    end
  end,
  schedule_ls_job = function(self, predictor_id, path, file_prefix, ends_with_dir, should_escape)
    return vimw.fn("jobstart", {
      {
        'ls',
        '-1',
        '-b',
        path
      },
      {
        on_stdout = "precog#sources#path#ls_callback",
        stdout_buffered = true,
        predictor_id = predictor_id,
        file_prefix = file_prefix,
        ends_with_dir = ends_with_dir,
        should_escape = should_escape
      }
    })
  end,
  ls_callback = function(self, job_id, opts, data)
    local predictor_id, file_prefix, ends_with_dir, should_escape
    predictor_id, file_prefix, ends_with_dir, should_escape = opts.predictor_id, opts.file_prefix, opts.ends_with_dir, opts.should_escape
    local children = { }
    for _index_0 = 1, #data do
      local line = data[_index_0]
      table.insert(children, (line:gsub("\\.", function(s)
        return self:unescape_chars(s)
      end)))
    end
    local candidates = self:filter_children(children, file_prefix, ends_with_dir, should_escape)
    return precog:add_candidates(self.source_name, predictor_id, candidates)
  end,
  escape_filename = function(self, filename)
    local escaped_filename = ""
    for char in filename:chars() do
      escaped_filename = escaped_filename .. self:escape_char(char)
    end
    return escaped_filename
  end,
  escape_char = function(self, char)
    return map_raw_to_escaped[char] or char
  end,
  unescape_chars = function(self, chars)
    return map_escaped_to_raw[chars] or chars
  end
}
map_raw_to_escaped = {
  ["\a"] = "\\a",
  ["\b"] = "\\b",
  ["\f"] = "\\f",
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
  ["\v"] = "\\v",
  ["\\"] = "\\\\",
  [" "] = "\\ "
}
do
  local _tbl_0 = { }
  for raw, escaped in pairs(map_raw_to_escaped) do
    _tbl_0[escaped] = raw
  end
  map_escaped_to_raw = _tbl_0
end
