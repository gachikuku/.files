-- Pure path detection for a byte position in terminal text.
local M = {}
local punctuation = { [","] = true, ["."] = true, [";"] = true, [":"] = true,
  [")"] = true, ["]"] = true, ["}"] = true, [">"] = true, ["`"] = true }

local function valid_input(text, byte_index)
  return type(text) == "string" and #text <= 1048576 and type(byte_index) == "number"
    and byte_index >= 1 and byte_index <= #text
end

local function local_path(value)
  if value:sub(1, 7) == "file://" then
    local host, path = value:match("^file://([^/]*)(/.*)$")
    if not path or (host ~= "" and host:lower() ~= "localhost") then return nil end
    value = path:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
    if value:find("%z") then return nil end
  elseif value:sub(1, 2) == "~/" then
    local home = os.getenv("HOME")
    if not home then return nil end
    value = home .. value:sub(2)
  end
  if value:sub(1, 1) == "/" then return value end
end

local function line_suffix(path)
  local base, line = path:match("^(.-):(%d+):%d+$")
  if not base then base, line = path:match("^(.-):(%d+)$") end
  if base and tonumber(line) > 0 then return base, tonumber(line) end
end

local function resolve(raw, is_file)
  while #raw > 0 do
    local path = local_path(raw)
    if path then
      if is_file(path) then return path end
      local base, line = line_suffix(path)
      if base and is_file(base) then return base, line end
    end
    if not punctuation[raw:sub(-1)] then break end
    raw = raw:sub(1, -2)
  end
end

local function hit(click, first, last, positions)
  if positions then first, last = positions[first], positions[last] end
  return first and last and click >= first and click <= last
end

local function quoted(text, click, positions, visit)
  local matched = false
  for _, quote in ipairs({ '"', "'", "`" }) do
    local offset = 1
    while true do
      local first, last, raw = text:find(quote .. "([^" .. quote .. "\r\n]+)" .. quote, offset)
      if not first then break end
      local suffix = text:sub(last + 1):match("^:%d+:%d+")
        or text:sub(last + 1):match("^:%d+") or ""
      if hit(click, first + 1, #suffix > 0 and last + #suffix or last - 1, positions) then
        matched = true
        local path, line = visit(raw .. suffix)
        if path then return path, line, true end
      end
      offset = last + 1
    end
  end
  return nil, nil, matched
end

local function scan_absolute(text, click, is_file, positions)
  local path, line = quoted(text, click, positions, function(raw) return resolve(raw, is_file) end)
  if path then return path, line end
  for _, pattern in ipairs({ "file://[^%s\"'`<>]+", "~/[^%s\"'`<>]+", "/[^%s\"'`<>]+" }) do
    local offset = 1
    while true do
      local first, last = text:find(pattern, offset)
      if not first then break end
      local before = first > 1 and text:sub(first - 1, first - 1) or ""
      -- Do not turn a slash inside an HTTP URL or another URI into a local path.
      if not before:match("[%w%._~:/%%%-]") and hit(click, first, last, positions) then
        path, line = resolve(text:sub(first, last), is_file)
        if path then return path, line end
      end
      offset = last + 1
    end
  end
end

-- Visit both the original text and 2/3-line windows around the click. Keeping
-- original byte positions makes clicks on wrapped continuations resolve too.
local function each_view(text, byte_index, visit)
  local path, line = visit(text)
  if path then return path, line end
  local lines, start, current = {}, 1, nil
  while start <= #text do
    local finish = text:find("\n", start, true) or (#text + 1)
    lines[#lines + 1] = { start, finish - 1 }
    if byte_index >= start and byte_index <= finish then current = #lines end
    start = finish + 1
  end
  if not current then return nil end
  for count = 2, 3 do
    for first = math.max(1, current - count + 1), math.min(current, #lines - count + 1) do
      local chars, positions = {}, {}
      for n = first, first + count - 1 do
        local a, b = lines[n][1], lines[n][2]
        if n > first then
          while a <= b and text:sub(a, a):match("[ \t]") do a = a + 1 end
        end
        if text:sub(b, b) == "\r" then b = b - 1 end
        for pos = a, b do
          chars[#chars + 1], positions[#positions + 1] = text:sub(pos, pos), pos
        end
      end
      path, line = visit(table.concat(chars), positions)
      if path then return path, line end
    end
  end
end

local function plausible_relative(raw)
  if raw == "" or raw:find("[%z\1-\31]") or raw:sub(1, 1) == "/" or raw:sub(1, 1) == "~"
      or raw:find("@", 1, true) or raw:find("://", 1, true) or raw:match("^www%.") then return false end
  -- A line suffix is allowed, but schemes (mailto:, https:, etc.) are not.
  local base = line_suffix(raw) or raw
  if base:find(":", 1, true) then return false end
  local name = base:match("([^/]+)$") or ""
  return base:sub(1, 2) == "./" or base:sub(1, 3) == "../" or base:find("/", 1, true) ~= nil
    or name:find("%.[^%.%s]+") ~= nil
end

local function scan_relative(text, click, positions, emit)
  local function variants(raw)
    -- Oversized tokens cannot name a local path. Skip their punctuation tail
    -- in linear time before generating only bounded candidate strings.
    local last = #raw
    while last > 4096 and punctuation[raw:sub(last, last)] do last = last - 1 end
    if last > 4096 then return end
    raw = raw:sub(1, last)
    while #raw > 0 do
      if plausible_relative(raw) then emit(raw) end
      local base, line = line_suffix(raw)
      if base and plausible_relative(base) then emit(base, line) end
      if not punctuation[raw:sub(-1)] then break end
      raw = raw:sub(1, -2)
    end
  end
  local _, _, in_quote = quoted(text, click, positions, variants)
  if in_quote then return end -- Keep a quoted path with spaces as one unit.
  local offset = 1
  while true do
    local first, last = text:find("[^%s\"'`<>]+", offset)
    if not first then break end
    while first <= last and text:sub(first, first):match("[%(%[%{]") do first = first + 1 end
    if hit(click, first, last, positions) then variants(text:sub(first, last)) end
    offset = last + 1
  end
end

-- Relative candidates intentionally do not claim a file exists. The caller
-- must resolve them against the clicked terminal's actual cwd and check it.
function M.candidates(text, byte_index)
  if not valid_input(text, byte_index) then return {} end
  local result, seen, bytes = {}, {}, 0
  local function emit(path, line)
    if #path > 4096 or #result >= 1024 or bytes + #path > 65536 then return end
    local key = path .. "\0" .. tostring(line or 0)
    if not seen[key] then
      seen[key] = true
      result[#result + 1] = { path = path, line = line }
      bytes = bytes + #path
    end
  end
  each_view(text, byte_index, function(view, positions)
    scan_relative(view, byte_index, positions, emit)
  end)
  return result
end

function M.find(text, byte_index, is_file, cwd)
  if not valid_input(text, byte_index) or type(is_file) ~= "function" then return nil end
  local path, line = each_view(text, byte_index, function(view, positions)
    return scan_absolute(view, byte_index, is_file, positions)
  end)
  if path then return path, line end
  if type(cwd) ~= "string" or cwd:sub(1, 1) ~= "/" or cwd:find("%z") then return nil end
  local prefix = cwd:gsub("/+$", "") .. "/"
  for _, candidate in ipairs(M.candidates(text, byte_index)) do
    local absolute = prefix .. candidate.path
    if is_file(absolute) then return absolute, candidate.line end
  end
end

return M
