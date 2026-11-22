-- One Rex CLI connection opens a local file in the clicked window's session.
local args = rex.args
local path, title, pid = args.path, args.title, tonumber(args.pid)
local line = tonumber(args.line or 0)
local relative = path == nil and type(args.candidates) == "table"
assert(relative or (type(path) == "string" and path:sub(1, 1) == "/" and not path:find("%z")),
  "A local file path is required")
assert(type(title) == "string" and pid and pid > 0, "The Rex window title and app PID are required")
assert(line and line >= 0 and line == math.floor(line), "Line must be a positive integer")

local function call(method, values)
  local result, err = rex.call(method, values)
  if not result then error(err or (method .. " failed"), 0) end
  return result
end

local session, longest, ambiguous = nil, -1, false
for _, candidate in ipairs(call("session.list").sessions or {}) do
  local label = candidate.label or ""
  local suffix = " - " .. label
  if #label > 0 and (title == label or title:sub(-#suffix) == suffix) then
    if #label > longest then
      session, longest, ambiguous = candidate, #label, false
    elseif #label == longest then
      ambiguous = true
    end
  end
end
assert(session, "Could not identify the Rex session from the clicked window title")
assert(not ambiguous, "The Rex window title matches more than one session")

local client
for _, candidate in ipairs(call("client.list").clients or {}) do
  if candidate.info and candidate.info.kind == "app" and candidate.principal
      and tonumber(candidate.principal.pid) == pid then
    assert(not client, "More than one Rex client matches the app PID")
    client = candidate.client_id
  end
end
assert(client, "The local Rex app is not connected")

local source_block, source_cwd
if relative then
  -- Hammerspoon starts outside a Rex shell, so attach before terminal RPCs.
  call("session.attach", { session_id = session.session_id })
  local view = call("session.view", { session_id = session.session_id })
  local panes = dofile(os.getenv("HOME") .. "/.config/rex/clicked-pane.lua")
  local source, error_message = panes.find(view, args.pane)
  assert(source, error_message)
  source_block = source.block_id
  if source.host_id then
    assert(source.host_id == call("server.status").host_id,
      "Relative file links require a pane running on this Mac")
  end
  local process = call("com.superlogical.terminal.process", {
    session_id = session.session_id, block_id = source_block, args = {},
  })
  source_cwd = process.foreground and process.foreground.cwd
  assert(type(source_cwd) == "string" and source_cwd:sub(1, 1) == "/",
    "Could not read the clicked pane's working directory")
  assert(#args.candidates <= 1024, "Too many file path candidates")
  for _, candidate in ipairs(args.candidates) do
    local name = candidate.path
    assert(type(name) == "string" and #name > 0 and #name <= 4096
      and name:sub(1, 1) ~= "/" and not name:find("%z"), "Invalid relative file path")
    local full = source_cwd:gsub("/+$", "") .. "/" .. name
    local handle = io.open(full, "rb")
    if handle then
      handle:close()
      path, line = full, tonumber(candidate.line or 0)
      break
    end
  end
  assert(path, "No matching file in " .. source_cwd)
  assert(line and line >= 0 and line == math.floor(line), "Invalid line number")
end

-- /bin/test is the system test executable on macOS. All arguments are literal.
local test, test_error = rex.exec({ "/bin/test", "-f", path, "-a", "-r", path })
assert(test and test.ok, test_error or "The file must be regular and readable")
local file, open_error = io.open(path, "rb")
assert(file, open_error or "The file must be readable")
local sample = file:read(65536) or ""
local at_end = file:read(1) == nil
file:close()
local image_extensions = {
  png = true, jpg = true, jpeg = true, gif = true, webp = true,
  bmp = true, tif = true, tiff = true, avif = true, heic = true,
  heif = true, jxl = true, svg = true, ico = true, icns = true,
  qoi = true, ppm = true, pgm = true, pbm = true, pnm = true,
  tga = true, jp2 = true, j2k = true, psd = true,
}
local extension = (path:match("%.([^./]+)$") or ""):lower()
local is_image = image_extensions[extension]
  or sample:sub(1, 8) == "\137PNG\r\n\26\n"
  or sample:sub(1, 3) == "\255\216\255"
  or sample:sub(1, 6) == "GIF87a" or sample:sub(1, 6) == "GIF89a"
  or (sample:sub(1, 4) == "RIFF" and sample:sub(9, 12) == "WEBP")

-- Image bytes belong to Yazi's terminal graphics renderer, not the text guard.
if not is_image then
  assert(not sample:find("[%z\1-\8\11\14-\31]"), "The file contains binary control characters")

  -- Validate the sample's UTF-8 without rejecting a character cut by its end.
  local i = 1
  while i <= #sample do
    local byte = sample:byte(i)
    local count = byte < 128 and 1 or (byte >= 194 and byte <= 223 and 2)
      or (byte >= 224 and byte <= 239 and 3) or (byte >= 240 and byte <= 244 and 4)
    assert(count, "The file is not UTF-8 text")
    if i + count - 1 > #sample then
      assert(not at_end, "The file is not UTF-8 text")
      break
    end
    for j = i + 1, i + count - 1 do
      local continuation = sample:byte(j)
      assert(continuation >= 128 and continuation <= 191, "The file is not UTF-8 text")
    end
    local second = sample:byte(i + 1) or 0
    assert(not ((byte == 224 and second < 160) or (byte == 237 and second > 159)
      or (byte == 240 and second < 144) or (byte == 244 and second > 143)), "The file is not UTF-8 text")
    i = i + count
  end
end

if args.validate_only then
  return { validated = true, viewer = is_image and "yazi" or "less",
    session_id = session.session_id, client_id = client,
    path = path, line = line, source_block_id = source_block, source_cwd = source_cwd }
end

local command
if is_image then
  command = { "/usr/bin/env",
    "YAZI_CONFIG_HOME=" .. os.getenv("HOME") .. "/.config/rex/image-viewer",
    "/run/current-system/sw/bin/yazi", "--", path }
else
  command = { "/usr/bin/less" }
  if line > 0 then command[#command + 1] = "+" .. line end
  command[#command + 1], command[#command + 2] = "--", path
end

local cwd, basename = path:match("^(.*)/([^/]+)$")
assert(basename, "The file path has no filename")
if cwd == "" then cwd = "/" end
local label = ((is_image and "Image " or "View ") .. basename):gsub("%c", " ")
-- Avoid cutting through a multibyte UTF-8 character in a long label.
if #label > 128 then
  local last = 128
  while label:byte(last + 1) and label:byte(last + 1) >= 128 and label:byte(last + 1) <= 191 do
    last = last - 1
  end
  label = label:sub(1, last)
end

if not relative then call("session.attach", { session_id = session.session_id }) end
local created = call("session.new_window", {
  session_id = session.session_id, window_label = label, focus = true,
  layout = rex.layout.block {
    flavor = "com.superlogical.terminal.shell",
    options = {
      shell = "none", cwd = cwd,
      command = command,
    },
  },
})
call("client.perform", {
  client_id = client, action = "session.select", origin = "api",
  args = { session_id = session.session_id, window_id = created.window_id },
})
return { session_id = session.session_id, window_id = created.window_id, block_ids = created.block_ids,
  path = path, source_block_id = source_block }
