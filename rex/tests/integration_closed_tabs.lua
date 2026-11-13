-- Real, disposable session test. Never selects a client or uses the user journal.
local root = os.getenv("HOME") .. "/.config/rex/"
local cli = "/Applications/Rex Beta.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"
local core = dofile(root .. "closed-tabs-core.lua")
local context = { path = os.tmpname() .. "-closed-tabs.json" }
local function call(method, args)
  args = args or {}
  if context.session and method ~= "session.create" then args.session_id = context.session end
  local result, err = rex.call(method, args)
  assert(result, err)
  return result
end
local function worker(operation, block)
  local result, err = rex.exec({ "/usr/bin/lockf", "-k", "-s", "-t", "0",
    context.path .. ".lock", cli, "--autostart=false", "do",
    root .. "closed-tabs-worker.lua", "--all", "--json", "operation=" .. operation,
    "session_id=" .. context.session, "state_path=" .. context.path,
    "block_id=" .. (block or "") }, { timeout = 20 })
  assert(result and result.ok, err or (result and result.stderr))
  return assert(rex.json.decode(result.stdout))
end
local function cat()
  return { block = { flavor = "com.superlogical.terminal.shell",
    options = { shell = "none", command = { "/bin/cat" } } } }
end
local ok, outcome = pcall(function()
  local created = call("session.create", { label = "rex-lua-retention-integration-" .. os.time(),
    initial_windows = { { layout = { split = { direction = "horizontal", ratio = 0.37,
      before = cat(), after = cat() } } } } })
  context.session = created.session_id
  call("session.attach")
  local first = call("session.view").windows[1]
  local floating = call("session.new_layer", { window_id = first.window_id, focus = false,
    bounds = { 0.2, 0.15, 0.4, 0.3 }, layout = cat() })
  call("session.set_layer_state", { layer_id = floating.layer_id, state = "minimized" })
  local original = call("session.view").windows[1]
  local pids, originals = {}, {}
  for _, layer in ipairs(original.layers) do
    for _, item in ipairs(layer.blocks) do
      originals[#originals + 1] = item.block_id
      local process = call("com.superlogical.terminal.process", { block_id = item.block_id, args = {} })
      pids[item.block_id] = assert(process.child and process.child.pid)
    end
  end
  local closed = worker("close", originals[1])
  assert(closed.changed)
  local current = call("session.list_blocks").blocks
  local detached = 0
  for _, item in ipairs(current) do if pids[item.block_id] then assert(item.placement == "detached"); detached = detached + 1 end end
  assert(detached == 3, "Original blocks were not retained")
  local reopened = worker("reopen")
  assert(reopened.changed)
  local target
  for _, window in ipairs(call("session.view").windows) do if window.window_id == reopened.window_id then target = window end end
  assert(target and #target.layers == 2)
  local split = target.layers[1].layout.split
  assert(split.direction == "horizontal" and math.abs(split.ratio - 0.37) < 0.000001)
  assert(target.layers[2].state == "minimized")
  for i, value in ipairs({ 0.2, 0.15, 0.4, 0.3 }) do assert(target.layers[2].bounds[i] == value) end
  for _, id in ipairs(originals) do
    local process = call("com.superlogical.terminal.process", { block_id = id, args = {} })
    assert(process.child.pid == pids[id], "A retained program was restarted")
  end
  assert(not worker("reopen").changed, "Repeated restore duplicated the tab")
  worker("close", originals[1])
  local data = core.read_state(context.path)
  data.sessions[context.session][1].closed_at = os.time() - core.retention_seconds
  core.write_state(context.path, data)
  local expired = worker("expire")
  assert(expired.closed_terminals == 3 and expired.expired_tabs == 1)
  for _, pid in pairs(pids) do
    local check = assert(rex.exec({ "/bin/kill", "-0", tostring(pid) }, { timeout = 1 }))
    assert(not check.ok, "Expired process remains alive")
  end
  return { preserved_processes = 3, split_and_float_restored = true,
    repeated_reopen_is_noop = true, expired_processes = 3 }
end)
if context.session then pcall(call, "session.destroy", {}) end
os.remove(context.path)
os.remove(context.path .. ".tmp")
os.remove(context.path .. ".lock")
if not ok then error(outcome, 0) end
return outcome
