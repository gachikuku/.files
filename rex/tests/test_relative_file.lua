-- Run: rex do ~/.files/rex/tests/test_relative_file.lua --json
-- Actual dispatcher/parser/filesystem; Rex session, process, and app RPCs are mocked.
local real_rex = rex
local home = assert(os.getenv("HOME"))
local source = home .. "/.config/rex/open-file.lua"
local parser = dofile(home .. "/.config/rex/file-at-click.lua")
local temporary = assert(real_rex.exec({ "/usr/bin/mktemp", "-d", "-t", "rex-relative-tests" }))
assert(temporary.ok, temporary.stderr)
local directory = temporary.stdout:gsub("[\r\n]+$", "")
local left_dir, right_dir = directory .. "/left", directory .. "/right"
assert(real_rex.exec({ "/bin/mkdir", left_dir, right_dir }).ok)
local files, cases = {}, {}
local function write(dir, name, content)
  local path = dir .. "/" .. name
  local file = assert(io.open(path, "wb")); assert(file:write(content)); file:close()
  files[#files + 1] = path
  return path
end
local foreground = { left = { cwd = left_dir }, right = { cwd = right_dir } }
local hosts = { left = "local-host", right = "local-host" }
local function view()
  return { active_window_id = "source-window", windows = {
    { window_id = "source-window", focused_block_id = "right", layers = {
      { kind = "tiled", blocks = {
        { block_id = "left", host_id = hosts.left }, { block_id = "right", host_id = hosts.right },
      }, layout = { split = {
        before = { block_id = "left", rect = { 0, 0, 0.5, 1 } },
        after = { block_id = "right", rect = { 0.5, 0, 0.5, 1 } },
      } } },
    } },
  } }
end
local function dispatch(values)
  local calls, created, queried, attached = {}, nil, nil, false
  values.title, values.pid = "Files - relative-tests", 4242
  rex = {
    args = values,
    exec = real_rex.exec,
    layout = { block = function(options) return options end },
    call = function(method, args)
      calls[#calls + 1] = method
      if method == "session.list" then
        return { sessions = { { session_id = "test-session", label = "relative-tests" } } }
      elseif method == "client.list" then
        return { clients = { { client_id = "test-client", info = { kind = "app" }, principal = { pid = 4242 } } } }
      elseif method == "session.view" then
        assert(attached, "Relative layout access must attach to its session first")
        assert(args.session_id == "test-session")
        return view()
      elseif method == "server.status" then
        return { host_id = "local-host" }
      elseif method == "com.superlogical.terminal.process" then
        assert(attached, "Terminal process RPC requires a session attachment")
        assert(args.session_id == "test-session")
        queried = args.block_id
        -- Deliberately offer irrelevant directories: only foreground.cwd is authoritative.
        return { foreground = foreground[queried], root = { cwd = right_dir }, cwd = left_dir }
      elseif method == "session.attach" then
        assert(not attached, "One request must not attach to the same session twice")
        assert(args.session_id == "test-session")
        attached = true
        return {}
      elseif method == "session.new_window" then
        created = args
        return { window_id = "mock-window", block_ids = { "mock-block" } }
      elseif method == "client.perform" then
        assert(args.action == "session.select" and args.args.window_id == "mock-window")
        return {}
      end
      error("Unexpected RPC: " .. method)
    end,
  }
  local ok, result = pcall(dofile, source)
  rex = real_rex
  return { ok = ok, result = result, calls = calls, created = created, queried = queried }
end
local function relative(name, side, line, validate)
  local shown = name .. (line and ":" .. line .. ":3" or "")
  return { candidates = parser.candidates(shown, 1),
    pane = { x = side == "right" and 0.5 or 0, y = 0, w = 0.5, h = 1 },
    validate_only = validate }
end
local function passed(name) cases[#cases + 1] = name end
local function succeeds(run)
  assert(run.ok, run.result)
  return run.result
end
local function failure(run, text)
  assert(not run.ok and tostring(run.result):find(text, 1, true), tostring(run.result))
  assert(not run.created, "Rejected request must not create a tab")
end

local ok, err = pcall(function()
  local left_file = write(left_dir, "same.json", '{"directory":"left"}\n')
  local right_file = write(right_dir, "same.json", '{"directory":"right"}\n')
  local only_left = write(left_dir, "only-left.json", '{}\n')
  local png = ("89504e470d0a1a0a0000000d4948445200000001000000010804000000b51c0c02"
    .. "0000000b4944415478da6364f80f00010501012718e3660000000049454e44ae426082")
    :gsub("..", function(byte) return string.char(tonumber(byte, 16)) end)
  local image_file = write(left_dir, "image.PNG", png)

  local left = dispatch(relative("same.json", "left", nil, true))
  local result = succeeds(left)
  assert(result.path == left_file and result.source_block_id == "left" and left.queried == "left")
  passed("clicked unfocused left pane uses its own cwd")

  local right = dispatch(relative("same.json", "right", nil, true))
  result = succeeds(right)
  assert(result.path == right_file and result.source_block_id == "right" and right.queried == "right")
  passed("same basename in right pane uses right cwd")

  result = succeeds(dispatch(relative("same.json" .. string.rep(")", 70), "left", nil, true)))
  assert(result.path == left_file)
  passed("long punctuation tail resolves beyond the former 64-candidate limit")

  foreground.left.cwd = right_dir
  result = succeeds(dispatch(relative("same.json", "left", nil, true)))
  assert(result.path == right_file and result.source_cwd == right_dir)
  foreground.left.cwd = left_dir
  passed("foreground cwd refreshed between requests")

  foreground.left = nil
  failure(dispatch(relative("same.json", "left", nil, true)), "working directory")
  foreground.left = { cwd = left_dir }
  passed("missing foreground cwd rejects without root/home fallback")

  failure(dispatch(relative("only-left.json", "right", nil, true)), "No matching file in " .. right_dir)
  passed("missing file never searches another pane cwd")

  local line_run = dispatch(relative("same.json", "left", 17, false))
  result = succeeds(line_run)
  local command = line_run.created.layout.options.command
  assert(result.path == left_file and command[1] == "/usr/bin/less" and command[2] == "+17"
    and command[3] == "--" and command[4] == left_file)
  passed("relative line suffix reaches less literally")

  local image_run = dispatch(relative("image.PNG", "left", nil, false))
  result = succeeds(image_run)
  command = image_run.created.layout.options.command
  assert(result.path == image_file and command[3] == "/run/current-system/sw/bin/yazi" and command[5] == image_file)
  passed("relative PNG routes to Yazi")

  hosts.left = "remote-host"
  local remote = dispatch(relative("same.json", "left", nil, true))
  failure(remote, "pane running on this Mac")
  assert(not remote.queried, "Remote pane must be rejected before local path resolution")
  hosts.left = "local-host"
  passed("remote pane rejected")

  local absolute = dispatch({ path = only_left, validate_only = true })
  result = succeeds(absolute)
  assert(result.path == only_left and #absolute.calls == 2)
  assert(absolute.calls[1] == "session.list" and absolute.calls[2] == "client.list")
  assert(not absolute.queried and not result.source_block_id)
  passed("absolute fast path performs no cwd/layout/status RPC")
end)
rex = real_rex
for _, path in ipairs(files) do os.remove(path) end
os.remove(left_dir); os.remove(right_dir); os.remove(directory)
assert(ok, err)
assert(#cases == 10, "All relative dispatcher regression cases must run")
return { passed = #cases, cases = cases, real_tabs_opened = 0 }
