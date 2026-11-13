-- Capture/apply only Rex appearance preferences through its Lua runtime.
--   rex do ~/.config/rex/appearance.lua operation=capture
--   rex do ~/.config/rex/appearance.lua operation=apply
-- Capture works while Rex is open. Apply requires its app to be closed;
-- this helper never quits/restarts the app or changes server/access settings.
-- The Go Mono Tmux font must already be installed on the destination Mac.
local args = rex.args or {}
local snapshot = args.snapshot or (os.getenv("HOME") .. "/.files/rex/.config/rex/appearance.json")
local domain = "com.superlogical.rex"
local defaults, plutil = "/usr/bin/defaults", "/usr/bin/plutil"

local types = {
  animationStyle = "string", appearance = "string", balancesSplitsOnCreation = "bool",
  customThemes = "themes", darkThemeID = "string", focusFollowsMouse = "bool",
  inactivePaneFadeMode = "string", interfaceStyle = "string", lightThemeID = "string",
  paneDensity = "string", showsActivePaneBorder = "bool", showsPaneHeaders = "bool",
  sidebarCollapsed = "bool", sidebarPosition = "string", sidebarShowsActivity = "bool",
  sidebarWidth = "float", tabIconCount = "int", tabIconTintMode = "string",
  tabStyle = "string", tabsFillAvailableSpace = "bool", terminalCharacterSpacing = "string",
  terminalCopyAnimation = "bool", terminalCursorBlinkIntervalMilliseconds = "int",
  terminalCursorBlinkUsesCustomInterval = "bool", terminalCursorStyleForced = "bool",
  terminalFontName = "string", terminalFontPointSize = "float", terminalFontSmoothing = "bool",
  terminalImproveTextContrast = "bool", terminalPaddingColor = "string",
  terminalPaddingX = "float", terminalPaddingY = "float", terminalSelectionRoundedCorners = "bool",
  terminalSmoothScrolling = "bool", terminalUseThemePalette = "bool", terminalUsesDisplayP3 = "bool",
  tintsPanesWithProgramBackground = "bool", usesPaneGlass = "bool",
  usesStandardInactiveWindowPaneStyles = "bool",
}
local keys, allowed = {}, {}
for name, kind in pairs(types) do
  local key = "Workspace." .. name
  keys[#keys + 1], allowed[key] = key, kind
end
table.sort(keys)

local function execute(argv, stdin, can_fail)
  local result, err = rex.exec(argv, { stdin = stdin, timeout = 10 })
  if not result then error(err) end
  if not result.ok and not can_fail then
    error(result.stderr ~= "" and result.stderr or "Command failed: " .. argv[1])
  end
  return result
end

local function preferences(can_be_missing)
  local result = execute({ defaults, "export", domain, "-" }, nil, can_be_missing)
  if not result.ok then return nil end
  return result.stdout
end

local function extract(xml, key)
  if not xml then return nil end
  local result = execute({ plutil, "-extract", key:gsub("%.", "\\."),
    "raw", "-n", "-o", "-", "-" }, xml, true)
  if not result.ok then return nil end
  return result.stdout
end

local function validate_themes(themes)
  assert(type(themes) == "table", "Custom themes must be an array.")
  local count = 0
  for key, theme in pairs(themes) do
    count = count + 1
    assert(type(key) == "number" and key >= 1 and key % 1 == 0,
      "Custom themes must be an array.")
    assert(type(theme) == "table" and type(theme.id) == "string" and theme.id ~= "",
      "Each custom theme needs an ID.")
  end
  assert(count == #themes, "Custom themes must be a dense array.")
end

local function custom_themes(xml)
  local encoded = extract(xml, "Workspace.customThemes")
  if not encoded then return {} end
  local decoded = execute({ "/usr/bin/base64", "-D" }, encoded).stdout
  local themes = rex.json.decode(decoded)
  validate_themes(themes)
  return themes
end

local function json_array(values)
  -- Rex's Lua JSON encoder turns an empty table into {}, so encode [] explicitly.
  local encoded = {}
  for _, value in ipairs(values) do encoded[#encoded + 1] = rex.json.encode(value) end
  return "[" .. table.concat(encoded, ",") .. "]"
end

local function validate(saved)
  assert(type(saved) == "table", "Appearance snapshot must be an object.")
  for key, value in pairs(saved) do
    local kind = allowed[key]
    assert(kind, "Unrecognized preference key: " .. tostring(key))
    if kind == "themes" then validate_themes(value)
    elseif kind == "string" then assert(type(value) == "string", "Expected a string: " .. key)
    elseif kind == "bool" then assert(type(value) == "boolean", "Expected a boolean: " .. key)
    else
      assert(type(value) == "number" and value == value and math.abs(value) ~= math.huge,
        "Expected a finite number: " .. key)
      if kind == "int" then assert(value % 1 == 0, "Expected an integer: " .. key) end
    end
  end
end

local function capture()
  local current = preferences(false)
  execute({ plutil, "-lint", "-" }, current)
  local saved = {}
  for _, key in ipairs(keys) do
    local kind = allowed[key]
    if kind ~= "themes" then
      local raw = extract(current, key)
      if raw ~= nil then
        if kind == "bool" then
          assert(raw == "true" or raw == "false", "Invalid boolean: " .. key)
          saved[key] = raw == "true"
        elseif kind == "int" or kind == "float" then
          saved[key] = assert(tonumber(raw), "Invalid number: " .. key)
        else saved[key] = raw end
      end
    end
  end
  local selected, themes = {}, {}
  if saved["Workspace.lightThemeID"] then selected[saved["Workspace.lightThemeID"]] = true end
  if saved["Workspace.darkThemeID"] then selected[saved["Workspace.darkThemeID"]] = true end
  for _, theme in ipairs(custom_themes(current)) do
    if selected[theme.id] then themes[#themes + 1] = theme end
  end
  saved["Workspace.customThemes"] = themes
  validate(saved)
  local lines, count = {}, 0
  for _, key in ipairs(keys) do
    if saved[key] ~= nil then
      count = count + 1
      local value = key == "Workspace.customThemes" and json_array(saved[key]) or rex.json.encode(saved[key])
      lines[#lines + 1] = "  " .. rex.json.encode(key) .. ": " .. value
    end
  end
  assert(count > 1, "No Rex appearance preferences found; snapshot was left intact.")
  local output = assert(io.open(snapshot .. ".tmp", "wb"))
  local written, err = output:write("{\n" .. table.concat(lines, ",\n") .. "\n}\n")
  local closed, close_err = output:close()
  assert(written, err)
  assert(closed, close_err)
  assert(os.rename(snapshot .. ".tmp", snapshot))
  return { captured = count, themes = #themes, path = snapshot }
end

local function apply()
  local input = assert(io.open(snapshot, "rb"))
  local text = input:read("*a")
  input:close()
  local saved = rex.json.decode(text)
  validate(saved) -- Validate every key and value before writing any preferences.
  local running = execute({ "/usr/bin/pgrep", "-f",
    "^/Applications/Rex[^/]*\\.app/Contents/MacOS/" }, nil, true)
  assert(running.code == 1, running.code == 0
    and "Quit the Rex app before applying its appearance preferences; it is still running."
    or "Could not check whether the Rex app is running.")
  local merged, index = custom_themes(preferences(true)), {}
  for position, theme in ipairs(merged) do index[theme.id] = position end
  for _, theme in ipairs(saved["Workspace.customThemes"] or {}) do
    local position = index[theme.id]
    if position then merged[position] = theme
    else merged[#merged + 1] = theme; index[theme.id] = #merged end
  end
  local count = 0
  for _, key in ipairs(keys) do
    local value, kind = saved[key], allowed[key]
    if value ~= nil then
      local flag, argument
      if kind == "themes" then
        flag = "-data"
        argument = json_array(merged):gsub(".", function(byte) return string.format("%02x", byte:byte()) end)
      else
        flag, argument = "-" .. kind, tostring(value)
      end
      execute({ defaults, "write", domain, key, flag, argument })
      count = count + 1
    end
  end
  return { applied = count, message = "Appearance preferences will load when Rex next opens." }
end

if args.operation == "capture" then return capture() end
if args.operation == "apply" then return apply() end
error("Use operation=capture or operation=apply. Optional snapshot=PATH chooses the JSON file.")
