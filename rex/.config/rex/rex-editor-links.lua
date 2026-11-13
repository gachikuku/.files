-- Command-Shift-click a local file in Rex to view it with less in a new Rex tab.
local M = {}
local root = os.getenv("HOME") .. "/.config/rex/"
local paths = dofile(root .. "file-at-click.lua")
local rex = "/Applications/Rex Beta.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"
local bundle = "com.superlogical.rex"
local types = hs.eventtap.event.types
local tasks, swallow = {}, false
local log = hs.logger.new("rex-file", "info")

local function fail(message)
  M.busy = false
  log.e(message)
  hs.alert.show("Rex file: " .. message)
end

local function run(program, args, callback)
  local task, deadline
  task = hs.task.new(program, function(code, stdout, stderr)
    tasks[task] = nil
    if deadline then deadline:stop() end
    if code ~= 0 then
      fail((stderr ~= "" and stderr or stdout):gsub("%s+$", ""))
      return
    end
    local ok, err = pcall(callback, stdout)
    if not ok then fail(tostring(err)) end
  end, args)
  if not task then fail("Could not start " .. program); return end
  local env = task:environment()
  env.REX_SESSION, env.REX_BLOCK, env.REX_CLIENT, env.REX_SERVER = nil, nil, nil, nil
  task:setEnvironment(env)
  tasks[task] = true
  if not task:start() then tasks[task] = nil; fail("Could not run " .. program); return end
  deadline = hs.timer.doAfter(5, function()
    if tasks[task] then
      task:setCallback(nil)
      task:terminate()
      tasks[task] = nil
      fail("Opening the file timed out.")
    end
  end)
end

local function regular_file(filename)
  return hs.fs.attributes(filename, "mode") == "file"
end

local function terminal_at(element, point, depth)
  if not element or depth > 8 then return end
  local frame = element.AXFrame
  if frame and (point.x < frame.x or point.y < frame.y
    or point.x >= frame.x + frame.w or point.y >= frame.y + frame.h) then return end
  if element.AXRole == "AXTextArea" and element.AXDescription == "Terminal" then return element end
  -- Rex's SwiftUI hit test returns its hosting group, so descend to the pane
  -- whose bounds contain this click instead of assuming the focused pane.
  for _, child in ipairs(element.AXChildren or {}) do
    local terminal = terminal_at(child, point, depth + 1)
    if terminal then return terminal end
  end
end

function M.fileAtPoint(point)
  local app = hs.application.frontmostApplication()
  if not app or app:bundleID() ~= bundle then return end
  local element = hs.axuielement.systemElementAtPosition(point)
  if not element or element:pid() ~= app:pid() then return end
  element = terminal_at(element, point, 0)
  if not element then return end
  local range = element:parameterizedAttributeValue("AXRangeForPosition", point)
  if not range or range.length == 0 then return end
  local text = element.AXValue
  if type(text) ~= "string" then return end
  -- Convert UTF-16 offsets locally, avoiding another call into Rex.
  local units, byteIndex = 0, nil
  for offset, codepoint in utf8.codes(text) do
    if units == range.location then byteIndex = offset; break end
    units = units + (codepoint > 0xffff and 2 or 1)
    if units > range.location then return end
  end
  if not byteIndex then return end
  local filename, line = paths.find(text, byteIndex, regular_file)
  if filename then return filename, line, element, app:pid() end
end

function M.open(filename, line, element, pid)
  if M.busy then return end
  local window = element and element.AXWindow
  local title = window and window.AXTitle
  if not title then fail("Could not identify the Rex window."); return end
  M.busy = true
  local args = hs.json.encode({ path = filename, line = line or 0, title = title, pid = pid })
  run(rex, { "--autostart=false", "do", root .. "open-file.lua", "--args", args, "--json" }, function(created)
    M.lastOpened = hs.json.decode(created)
    M.busy = false
  end)
end

function M.handleEvent(event)
  local kind, point = event:getType(), event:location()
  if kind == types.leftMouseDown then
    swallow = false
    local flags = event:getFlags()
    if not flags.cmd or not flags.shift or flags.alt or flags.ctrl then return false end
    local filename, line, element, pid = M.fileAtPoint(point)
    if not filename then return false end
    -- Start on press, so holding/releasing the mouse adds no delay.
    swallow = true
    M.open(filename, line, element, pid)
    return true
  end
  local handled = swallow
  if kind == types.leftMouseUp then swallow = false end
  return handled
end

function M.start()
  if not hs.accessibilityState() then return false end
  M.tap = hs.eventtap.new({types.leftMouseDown, types.leftMouseUp, types.leftMouseDragged}, function(event)
    local ok, handled = pcall(M.handleEvent, event)
    if not ok then log.e(tostring(handled)); swallow = false; return false end
    return handled
  end):start()
  M.watchdog = hs.timer.doEvery(30, function()
    if hs.accessibilityState() and not M.tap:isEnabled() then M.tap:start() end
  end)
  return M.tap:isEnabled()
end

function M.stop()
  if M.tap then M.tap:stop() end
  if M.watchdog then M.watchdog:stop() end
  for task in pairs(tasks) do task:setCallback(nil); task:terminate() end
  tasks = {}
  M.busy = false
end

M.start()
return M
