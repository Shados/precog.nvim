export precog
require 'precog'
require 'earthshine.string'
vimw = require 'facade'
Path = require 'earthshine.path'

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

    -- Scan the portion of the line leading to the current cursor position,
    -- looking for valid POSIX paths that end at the curpos.
    -- We also need to work out whether the path up to the curpos is:
    -- a) Within a valid pair of quotes, or after an opening quote
    -- b) Unquoted

    -- The longest non-empty string of non-NUL bytes leading up to the curpos
    maybe_path = before_cursor\match "[^%z]+$"

    return unless maybe_path
    first, quoted = @find_path_bounds maybe_path
    return unless first != nil
    path = maybe_path\sub first, -1
    unless quoted
      -- Unescape any escaped characters
      path = path\gsub "\\.", (s) -> @unescape_chars s
      -- If not quoted, we assume explicit escaping of spaces and some other
      -- characters in the path (using \ as the escape character).

    ends_with_dir = (path\at #path) == "/"
    local ls_path, file_prefix
    if ends_with_dir
      ls_path = path
      file_prefix = nil
    else
      ls_path = Path\parse_parent path
      file_prefix = Path\parse_name path

    @schedule_ls_job timer_id, ls_path, file_prefix, (not quoted)

  find_path_bounds: (path) =>
    first, last, quoted = 0, #path, false
    local last_char, char
    for index = 1, #path
      char = path\at index
      if @valid_quotes[char] and last_char != "\\"
        quoted = not quoted
        first = index + 1
    if first > last
      -- Should only happen with a path like: /some/path/"
      -- With curpos at the very end
      return nil, true
    else
      return first, quoted

  schedule_ls_job: (predictor_id, path, file_prefix, should_escape) =>
    path_prefix = "/" if path == "."
    vimw.fn "jobstart", { {'ls', '-1', '-b', path}, {
      on_stdout: "precog#sources#path#ls_callback"
      stdout_buffered: true
      :predictor_id
      :file_prefix
      :should_escape
      :path_prefix
    }}

  -- TODO figure out a way to handle overly-large directories more cleanly.
  -- Maybe look into using an unbuffered callback to add predictions
  -- incrementally?
  ls_callback: (job_id, opts, data) =>
    import predictor_id, file_prefix, should_escape, path_prefix from opts

    -- Unescape the returned child files
    children = {}
    for line in *data
      -- Replace escaped characters
      table.insert children, (line\gsub "\\.", (s) -> @unescape_chars s)

    -- Check the returned children of the given dir_path and see if any match
    -- using the last element in the typed path as a prefix (if the last
    -- element is a file)
    candidates = @filter_children children, file_prefix, should_escape, path_prefix

    precog\add_candidates @source_name, predictor_id, candidates

  filter_children: (children, file_prefix, should_escape, path_prefix) =>
    matches = {}
    for filename in *children
      continue if filename == "." or filename == ".." or filename == ""
      if should_escape
        filename = @escape_filename filename
      else
        -- Still need to escape the escape character in quoted paths
        filename = @escape_escapes filename
      if path_prefix
        filename = path_prefix .. filename
      if not file_prefix
        table.insert matches, filename
      elseif (filename\sub 1, #file_prefix) == file_prefix
        table.insert matches, filename
    return matches

  escape_filename: (filename) =>
    escaped_filename = ""
    for char in filename\chars!
      escaped_filename ..= @escape_char char
    return escaped_filename

  escape_escapes: (filename) =>
    escaped_filename = ""
    for char in filename\chars!
      if char == "\\"
        escaped_filename ..= @escape_char char
      else
        escaped_filename ..= char
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

return precog.path
