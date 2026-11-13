-- Run with: rex do ~/.files/rex/tests/test_appearance.lua
-- All defaults writes are mocked. Temporary snapshot files are removed afterward.
local real_rex = rex
local home = os.getenv("HOME")
local helper = home .. "/.config/rex/appearance.lua"
local fixture_path = home .. "/.files/rex/.config/rex/appearance.json"
local fixture_file = assert(io.open(fixture_path, "rb"))
local fixture = real_rex.json.decode(fixture_file:read("*a"))
fixture_file:close()
local made = assert(real_rex.exec({ "/usr/bin/mktemp", "-t", "rex-appearance-tests" }))
assert(made.ok, made.stderr)
local path = made.stdout:gsub("[\r\n]+$", "")
local writes, running, missing, current, existing

local function read_snapshot()
  local file = assert(io.open(path, "rb"))
  local text = file:read("*a")
  file:close()
  return real_rex.json.decode(text), text
end

local function write_snapshot(value)
  local file = assert(io.open(path, "wb"))
  assert(file:write(real_rex.json.encode(value)))
  file:close()
end

local function reset()
  writes, running, missing = {}, false, false
  current = real_rex.json.decode(real_rex.json.encode(fixture))
  existing = { { id = "existing-other-theme", name = "Existing" },
    { id = fixture["Workspace.lightThemeID"], name = "Older version" } }
end

local function result(stdout, code)
  code = code or 0
  return { ok = code == 0, code = code, stdout = stdout or "", stderr = code == 0 and "" or "mock failure" }
end

local function execute(argv, options)
  if argv[1] == "/usr/bin/pgrep" then return result("", running and 0 or 1) end
  if argv[1] == "/usr/bin/defaults" then
    assert(argv[3] == "com.superlogical.rex")
    if argv[2] == "export" then return result("MOCK-PLIST", missing and 1 or 0) end
    assert(argv[2] == "write")
    assert(argv[4]:sub(1, 10) == "Workspace.")
    writes[#writes + 1] = argv
    return result()
  end
  if argv[1] == "/usr/bin/plutil" then
    assert(options.stdin == "MOCK-PLIST")
    if argv[2] == "-lint" then return result() end
    assert(argv[2] == "-extract" and argv[4] == "raw")
    local key = argv[3]:gsub("\\%.", ".")
    if key == "Workspace.customThemes" then return result("MOCK-BASE64") end
    local value = current[key]
    if value == nil then return result("", 1) end
    return result(tostring(value))
  end
  if argv[1] == "/usr/bin/base64" then
    assert(argv[2] == "-D" and options.stdin == "MOCK-BASE64")
    return result(real_rex.json.encode(existing))
  end
  error("Unexpected external command: " .. table.concat(argv, " "))
end

local function invoke(operation)
  rex = { args = { operation = operation, snapshot = path },
    exec = execute, json = real_rex.json }
  local ok, value = pcall(assert(loadfile(helper)))
  rex = real_rex
  return ok, value
end

local ok, err = pcall(function()
  reset()
  write_snapshot(fixture)
  local applied, outcome = invoke("apply")
  assert(applied, outcome)
  assert(outcome.applied == 39 and #writes == 39)
  local themes
  for _, argv in ipairs(writes) do
    if argv[4] == "Workspace.terminalFontPointSize" then assert(argv[5] == "-float") end
    if argv[4] == "Workspace.tabIconCount" then assert(argv[5] == "-int") end
    if argv[4] == "Workspace.terminalFontSmoothing" then assert(argv[5] == "-bool") end
    if argv[4] == "Workspace.customThemes" then
      assert(argv[5] == "-data")
      themes = real_rex.json.decode((argv[6]:gsub("%x%x", function(hex)
        return string.char(tonumber(hex, 16))
      end)))
    end
  end
  assert(#themes == 2 and themes[1].id == "existing-other-theme")
  assert(themes[2].name == fixture["Workspace.customThemes"][1].name)

  reset()
  running = true
  assert(not invoke("apply") and #writes == 0, "Running app must prevent writes")

  reset()
  local invalid = real_rex.json.decode(real_rex.json.encode(fixture))
  invalid["rex.client.remoteControl"] = true
  write_snapshot(invalid)
  assert(not invoke("apply") and #writes == 0, "Unknown keys must prevent every write")
  invalid["rex.client.remoteControl"] = nil
  invalid["Workspace.terminalFontPointSize"] = "large"
  write_snapshot(invalid)
  assert(not invoke("apply") and #writes == 0, "Invalid types must prevent every write")

  reset()
  local captured, summary = invoke("capture")
  assert(captured, summary)
  assert(summary.captured == 39 and summary.themes == 1 and #writes == 0)
  local saved = read_snapshot()
  assert(#saved["Workspace.customThemes"] == 1)
  assert(saved["Workspace.customThemes"][1].id == fixture["Workspace.lightThemeID"])

  current["Workspace.lightThemeID"] = "builtin-light"
  current["Workspace.darkThemeID"] = "builtin-dark"
  assert(invoke("capture"))
  local _, text = read_snapshot()
  assert(text:find('"Workspace.customThemes": %[%]'), "Empty themes must serialize as []")
  local before = text
  missing = true
  assert(not invoke("capture") and #writes == 0)
  local _, after = read_snapshot()
  assert(after == before, "Failed capture must preserve snapshot")
end)
rex = real_rex
os.remove(path)
os.remove(path .. ".tmp")
assert(ok, err)
return { passed = 7, actual_preference_writes = 0 }
