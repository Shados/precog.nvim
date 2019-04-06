export precog
require 'precog'
require 'earthshine.string'
vimw = require 'facade'
utils = require 'precog.utils'
p = require 'earthshine.path'
inspect = require 'vendor.inspect'

local *

precog.path =
  source_name: "path"
  valid_quotes:
    ["'"]: true
    ["\""]: true
    ["`"]: true

  register: () =>
    precog\log "path:register() called"
    precog\register_source @source_name,
      predictor: "precog#sources#path#predictor"
      priority: 5

  predictor: (timer_id) =>
    change_data = precog.change_data[timer_id]
    import line_content, before_cursor, start_col, col, filepath from change_data

    -- Scan the line up to the current cursor position, looking for valid POSIX
    -- paths.
    -- Two code-paths, based on if the character *after* the cursor is a
    -- quotation mark (', ", or `). If it is:
    -- - We assume the path is quoted, look for a matching start quote, and
    --   then look for a valid path within that.
    -- - If not, or if there turns out to be no matching start quote, we assume
    --   explicit escaping of spaces in path (using a \).
    local path, quoted

    after_cursor = line_content\at col

    if @valid_quotes[after_cursor]
      quote = after_cursor
      path = @find_inner_path before_cursor, quote

    unless path
      path = @find_unquoted_path before_cursor
      quoted = false
    else
      quoted = true

    parent_dir_path, file_prefix, ends_with_dir = @get_path_properties path, filepath
    @schedule_ls_job timer_id, parent_dir_path, file_prefix, ends_with_dir, not quoted

  get_path_properties: (path, filepath) =>
    dir_path = if p.is_absolute path
      "/"
    else
      p.parse_dir filepath
    if (dir_path\at #dir_path) != "/"
      dir_path ..= "/"

    path_elements = {}
    for element in p.iterate path
      table.insert path_elements, element

    ends_with_dir = #path == 0 or (path\at #path) == '/'
    file_prefix = unless ends_with_dir
      path_elements[#path_elements]
    else
      nil

    -- If we have directory elements, add them to the dir_path
    loop_end = if ends_with_dir
      #path_elements
    else
      #path_elements - 1
    for i = 1, loop_end
      element = path_elements[i]
      dir_path ..= element .. "/"

    return dir_path, file_prefix, ends_with_dir

  filter_children: (children, file_prefix, ends_with_dir, should_escape) =>
    matches = {}
    for filename in *children
      continue if filename == "." or filename == ".." or filename == ""
      if should_escape
        filename = @escape_filename filename
      if ends_with_dir
        table.insert matches, filename
      elseif (filename\sub 1, #file_prefix) == file_prefix
        table.insert matches, filename
    return matches

  -- A valid unix path is 1 or more non-NUL characters. Really. In this case
  -- we're also looking for potential paths, so 0 or more.
  path_pattern: "([^%z]*)"

  -- Returns: path within quoted string str (excluding closing quote), or nil
  find_inner_path: (str, quote) =>
    -- Scan string, look for and store the index of the last unescaped
    -- matching quote
    local last_escape, last_quote
    for index = 1, #str
      char = str\at index
      if char == "\\"
        last_escape = index
      elseif char == quote and last_escape != index - 1
        last_quote = index

    path_start = if last_quote
      -- Advance index by 1 to reach the first character within the quoted
      -- string
      last_quote + 1
    else
      nil

    if path_start
      -- Take the segment within the quotes and determine if it is a valid
      -- path
      inner_string = str\sub path_start, #str
      if inner_string\match @path_pattern
        return inner_string
    return nil

  find_unquoted_path: (str) =>
    -- Find the last sequence of non-NUL characters in the input string
    str = utils.get_last_match @path_pattern, str
    -- Unescape any escaped characters and return
    if str
      return str\gsub "\\.", (s) -> @unescape_chars s
    else
      return ""

  schedule_ls_job: (predictor_id, path, file_prefix, ends_with_dir, should_escape) =>
    vimw.fn "jobstart", { {'ls', '-1', '-b', path}, {
      on_stdout: "precog#sources#path#ls_callback"
      stdout_buffered: true
      :predictor_id
      :file_prefix
      :ends_with_dir
      :should_escape
    }}

  -- TODO figure out a way to handle overly-large directories more cleanly.
  -- Maybe look into using an unbuffered callback to add predictions
  -- incrementally?
  ls_callback: (job_id, opts, data) =>
    import predictor_id, file_prefix, ends_with_dir, should_escape from opts

    -- Unescape the returned child files
    children = {}
    for line in *data
      -- Replace escaped characters
      table.insert children, (line\gsub "\\.", (s) -> @unescape_chars s)

    -- Check the returned children of the given dir_path and see if any match
    -- using the last element in the typed path as a prefix (if the last
    -- element is a file)
    candidates = @filter_children children, file_prefix, ends_with_dir, should_escape

    precog\add_candidates @source_name, predictor_id, candidates

  escape_filename: (filename) =>
    escaped_filename = ""
    for char in filename\chars!
      escaped_filename ..= @escape_char char
    return escaped_filename

  -- Returns a C-style escaped version of the input character
  -- TODO handle utf-8
  escape_char: (char) =>
    return map_raw_to_escaped[char] or char

  unescape_chars: (chars) =>
    return map_escaped_to_raw[chars] or chars

map_raw_to_escaped = {
  ["\a"]: "\\a"
  ["\b"]: "\\b"
  ["\f"]: "\\f"
  ["\n"]: "\\n"
  ["\r"]: "\\r"
  ["\t"]: "\\t"
  ["\v"]: "\\v"
  ["\\"]: "\\\\"
  [" "]: "\\ "
}
map_escaped_to_raw = {escaped, raw for raw, escaped in pairs map_raw_to_escaped}
