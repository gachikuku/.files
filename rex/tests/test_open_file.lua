-- Run: rex do ~/.files/rex/tests/test_open_file.lua --json
-- Exercises the real file dispatcher with real files; all Rex tab/app calls are mocked.
local real_rex = rex
local home = assert(os.getenv("HOME"))
local source = home .. "/.config/rex/open-file.lua"
local temporary = assert(real_rex.exec({ "/usr/bin/mktemp", "-d", "-t", "rex-open-file-tests" }))
assert(temporary.ok, temporary.stderr)
local directory = temporary.stdout:gsub("[\r\n]+$", "")
local files, cases = {}, {}

local function write(name, contents)
  local path = directory .. "/" .. name
  local file = assert(io.open(path, "wb"))
  assert(file:write(contents)); file:close()
  files[#files + 1] = path
  return path
end

local function dispatch(path, line, validate_only)
  local created, selected, mutation_count = nil, nil, 0
  rex = {
    args = { path = path, line = line or 0, title = "Files - rex-image-tests",
      pid = 4242, validate_only = validate_only },
    exec = real_rex.exec,
    layout = { block = function(values) return values end },
    call = function(method, values)
      if method == "session.list" then
        return { sessions = { { label = "rex-image-tests", session_id = "test-session" } } }
      elseif method == "client.list" then
        return { clients = { { info = { kind = "app" }, principal = { pid = 4242 },
          client_id = "test-client" } } }
      end
      mutation_count = mutation_count + 1
      if method == "session.attach" then
        assert(values.session_id == "test-session")
        return {}
      elseif method == "session.new_window" then
        created = values
        return { window_id = "test-window", block_ids = { "test-block" } }
      elseif method == "client.perform" then
        selected = values
        return {}
      end
      error("Unexpected Rex operation: " .. method)
    end,
  }
  local ok, result = pcall(dofile, source)
  rex = real_rex
  if not ok then return nil, result, mutation_count end
  if validate_only then
    assert(mutation_count == 0, "Validation must not open/select a tab")
  else
    assert(created and selected and mutation_count == 3)
    assert(created.layout.options.shell == "none", "Do not interpret file paths as shell code")
    assert(selected.action == "session.select" and selected.args.window_id == "test-window")
  end
  return { result = result, created = created }, nil, mutation_count
end

local function image_command(path)
  local run, err = dispatch(path)
  assert(run, err)
  local args = run.created.layout.options.command
  assert(#args == 5 and args[1] == "/usr/bin/env")
  assert(args[2] == "YAZI_CONFIG_HOME=" .. home .. "/.config/rex/image-viewer")
  assert(args[3] == "/run/current-system/sw/bin/yazi" and args[4] == "--" and args[5] == path)
  assert(run.created.window_label:sub(1, 6) == "Image ")
  cases[#cases + 1] = path:match("[^/]+$")
end

local ok, err = pcall(function()
  -- Valid 1x1 PNG, including the binary controls that formerly triggered the text guard.
  local png = ("89504e470d0a1a0a0000000d4948445200000001000000010804000000b51c0c02"
    .. "0000000b4944415478da6364f80f00010501012718e3660000000049454e44ae426082")
    :gsub("..", function(byte) return string.char(tonumber(byte, 16)) end)
  image_command(write("image.png", png))
  image_command(write("Image 'quoted' $(not-a-command).PNG", png))
  image_command(write("image-without-extension", png))

  local read_only = write("read-only.png", png)
  assert(real_rex.exec({ "/bin/chmod", "400", read_only }).ok)
  image_command(read_only)

  local text = write("plain text.json", '{"message":"hello"}\n')
  local run, failure = dispatch(text, 12)
  assert(run, failure)
  local command = run.created.layout.options.command
  assert(#command == 4 and command[1] == "/usr/bin/less" and command[2] == "+12")
  assert(command[3] == "--" and command[4] == text)
  assert(run.created.window_label == "View plain text.json")
  cases[#cases + 1] = "text +line"

  for _, pair in ipairs({ { read_only, "yazi" }, { text, "less" } }) do
    local validated, validation_error = dispatch(pair[1], 0, true)
    assert(validated, validation_error)
    assert(validated.result.validated and validated.result.viewer == pair[2])
    cases[#cases + 1] = "validation " .. pair[2]
  end

  local binary = write("unrecognized.bin", "\0\1\2\3binary data")
  local rejected, rejection, mutations = dispatch(binary)
  assert(not rejected and rejection:find("binary control characters", 1, true))
  assert(mutations == 0, "Unsupported binary must not create a text tab")
  cases[#cases + 1] = "unknown binary rejected"
end)

rex = real_rex
for _, path in ipairs(files) do os.remove(path) end
os.remove(directory)
assert(ok, err)
assert(#cases == 8, "All regression cases must run")
return { passed = #cases, cases = cases, real_tabs_opened = 0 }
