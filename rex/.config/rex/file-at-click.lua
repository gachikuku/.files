-- Pure path detection for a byte position in terminal text.
local M = {}
local punctuation = { [","] = true, ["."] = true, [";"] = true, [":"] = true,
  [")"] = true, ["]"] = true, ["}"] = true, [">"] = true, ["`"] = true }

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

local function resolve(raw, is_file)
  while #raw > 0 do
    local path = local_path(raw)
    if path then
      if is_file(path) then return path end
      local base, line = path:match("^(.-):(%d+):%d+$")
      if not base then base, line = path:match("^(.-):(%d+)$") end
      if base and tonumber(line) > 0 and is_file(base) then
        return base, tonumber(line)
      end
    end
    if not punctuation[raw:sub(-1)] then break end
    raw = raw:sub(1, -2)
  end
end

local function scan(text, click, is_file, positions)
  local function hit(first, last)
    if positions then first, last = positions[first], positions[last] end
    return first and last and click >= first and click <= last
  end

  -- Quoting makes spaces part of a path. Quotes themselves are not required
  -- to be included in a terminal's clickable range.
  for _, quote in ipairs({ '"', "'" }) do
    local offset = 1
    while true do
      local first, last, raw = text:find(quote .. "([^" .. quote .. "\r\n]+)" .. quote, offset)
      if not first then break end
      local suffix = text:sub(last + 1):match("^:%d+:%d+")
        or text:sub(last + 1):match("^:%d+") or ""
      if hit(first + 1, #suffix > 0 and last + #suffix or last - 1) then
        local path, line = resolve(raw .. suffix, is_file)
        if path then return path, line end
      end
      offset = last + 1
    end
  end

  for _, pattern in ipairs({ "file://[^%s\"'<>]+", "~/[^%s\"'<>]+", "/[^%s\"'<>]+" }) do
    local offset = 1
    while true do
      local first, last = text:find(pattern, offset)
      if not first then break end
      local before = first > 1 and text:sub(first - 1, first - 1) or ""
      -- Do not interpret a slash inside https://host/path or another URI as
      -- the start of a local path.
      if not before:match("[%w%._~:/%%%-]") and hit(first, last) then
        local path, line = resolve(text:sub(first, last), is_file)
        if path then return path, line end
      end
      offset = last + 1
    end
  end
end

function M.find(text, byte_index, is_file)
  if type(text) ~= "string" or #text > 1048576 or type(byte_index) ~= "number"
      or byte_index < 1 or byte_index > #text or type(is_file) ~= "function" then return nil end
  local path, line = scan(text, byte_index, is_file)
  if path then return path, line end

  -- Accessibility text may insert newlines at soft wraps. Try only windows
  -- of two or three lines around the click; a joined path must actually exist.
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
      path, line = scan(table.concat(chars), byte_index, is_file, positions)
      if path then return path, line end
    end
  end
end

return M
