require('precog')
require('earthshine.string')
local vimw = require('facade')
local Path = require('earthshine.path')
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
    local maybe_path = before_cursor:match("[^%z]+$")
    if not (maybe_path) then
      return 
    end
    local first, quoted = self:find_path_bounds(maybe_path)
    if not (first ~= nil) then
      return 
    end
    local path = maybe_path:sub(first, -1)
    if not (quoted) then
      path = path:gsub("\\.", function(s)
        return self:unescape_chars(s)
      end)
    end
    local ends_with_dir = (path:at(#path)) == "/"
    local ls_path, file_prefix
    if ends_with_dir then
      ls_path = path
      file_prefix = nil
    else
      ls_path = Path:parse_parent(path)
      file_prefix = Path:parse_name(path)
    end
    return self:schedule_ls_job(timer_id, ls_path, file_prefix, (not quoted))
  end,
  find_path_bounds = function(self, path)
    local first, last, quoted = 0, #path, false
    local last_char, char
    for index = 1, #path do
      char = path:at(index)
      if self.valid_quotes[char] and last_char ~= "\\" then
        quoted = not quoted
        first = index + 1
      end
    end
    if first > last then
      return nil, true
    else
      return first, quoted
    end
  end,
  schedule_ls_job = function(self, predictor_id, path, file_prefix, should_escape)
    local path_prefix
    if path == "." then
      path_prefix = "/"
    end
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
        should_escape = should_escape,
        path_prefix = path_prefix
      }
    })
  end,
  ls_callback = function(self, job_id, opts, data)
    local predictor_id, file_prefix, should_escape, path_prefix
    predictor_id, file_prefix, should_escape, path_prefix = opts.predictor_id, opts.file_prefix, opts.should_escape, opts.path_prefix
    local children = { }
    for _index_0 = 1, #data do
      local line = data[_index_0]
      table.insert(children, (line:gsub("\\.", function(s)
        return self:unescape_chars(s)
      end)))
    end
    local candidates = self:filter_children(children, file_prefix, should_escape, path_prefix)
    return precog:add_candidates(self.source_name, predictor_id, candidates)
  end,
  filter_children = function(self, children, file_prefix, should_escape, path_prefix)
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
        else
          filename = self:escape_escapes(filename)
        end
        if path_prefix then
          filename = path_prefix .. filename
        end
        if not file_prefix then
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
  escape_filename = function(self, filename)
    local escaped_filename = ""
    for char in filename:chars() do
      escaped_filename = escaped_filename .. self:escape_char(char)
    end
    return escaped_filename
  end,
  escape_escapes = function(self, filename)
    local escaped_filename = ""
    for char in filename:chars() do
      if char == "\\" then
        escaped_filename = escaped_filename .. self:escape_char(char)
      else
        escaped_filename = escaped_filename .. char
      end
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
return precog.path
