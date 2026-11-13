-- Run using rex do; all session operations are mocked and clipboard untouched.
local real_rex = rex
local snapshot = dofile(os.getenv("HOME") .. "/.config/rex/copy-snapshot.lua")
local temp = assert(rex.exec({ "/usr/bin/mktemp", "-d", "-t", "rex-copy-tests" }))
assert(temp.ok, temp.stderr)
snapshot.cache = temp.stdout:gsub("[\r\n]+$", "")
local directory = snapshot.cache .. "/snapshot-test123"
assert(rex.exec({ "/bin/mkdir", directory }).ok)
local context = { session = "s", source = "source", window = "w", zoomed = true, overlay = "overlay" }
local function write(path, text)
  local file = assert(io.open(path, "wb")); assert(file:write(text)); file:close()
end
local function exists(path)
  local file = io.open(path, "rb")
  if file then file:close(); return true end
  return false
end
local ok, err = pcall(function()
  assert(snapshot.valid_directory(directory))
  assert(not snapshot.valid_directory(snapshot.cache .. "/snapshot-../outside"))
  assert(not snapshot.valid_directory(snapshot.cache .. "/snapshot-"))
  assert(not pcall(snapshot.clean, "/tmp"))
  write(directory .. "/context.json", real_rex.json.encode(context))
  write(snapshot.cache .. "/overlay-overlay", directory .. "\n")
  assert(snapshot.for_block("overlay").source == "source")
  assert(snapshot.for_block("../overlay") == nil)
  assert(snapshot.for_block("source") == nil)

  local calls = {}
  local view = { active_window_id = "w", windows = { { window_id = "w", focused_block_id = "overlay" } } }
  rex = { json = real_rex.json, session = {
    view = function() return view end,
    focus_block = function(args) calls[#calls + 1] = { "focus", args.block_id }; return {} end,
    zoom_block = function(args) calls[#calls + 1] = { "zoom", args.block_id }; return {} end,
  } }
  snapshot.restore(context)
  assert(#calls == 2 and calls[1][2] == "source" and calls[2][1] == "zoom")
  calls = {}; view.active_window_id = "another-tab"
  snapshot.restore(context); assert(#calls == 0, "Must not steal another tab's focus")
  view.active_window_id = "w"; view.windows[1].focused_block_id = "another-pane"
  snapshot.restore(context); assert(#calls == 0, "Must not steal another pane's focus")
  rex = real_rex

  -- Another snapshot may already own this marker; only remove our own files.
  write(snapshot.cache .. "/overlay-overlay", snapshot.cache .. "/snapshot-other\n")
  write(directory .. "/scrollback.txt", "private text")
  snapshot.clean(directory, context)
  assert(not exists(directory .. "/scrollback.txt"))
  assert(exists(snapshot.cache .. "/overlay-overlay"), "Must preserve another snapshot's marker")

  assert(rex.exec({ "/bin/mkdir", directory }).ok)
  write(directory .. "/context.json", real_rex.json.encode(context))
  write(snapshot.cache .. "/overlay-overlay", directory .. "\n")
  snapshot.closed("overlay")
  assert(not exists(snapshot.cache .. "/overlay-overlay"))
  assert(snapshot.context(directory) == nil)
end)
rex = real_rex
snapshot.clean(directory, context)
os.remove(snapshot.cache .. "/overlay-overlay")
os.remove(snapshot.cache)
assert(ok, err)
return { passed = 8, clipboard = "untouched" }
