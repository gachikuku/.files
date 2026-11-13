-- Run with: rex --autostart=false do ~/.files/rex/tests/test_closed_tabs.lua --all
-- APIs/state writes are in-memory fakes; no user terminals or clipboard change.
local core = dofile(os.getenv("HOME") .. "/.files/rex/.config/rex/closed-tabs-core.lua")
local NOW, SID = 2000000000, "session:test"
local TTL = core.retention_seconds
local passed = {}

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for k, v in pairs(value) do result[k] = copy(v) end
  return result
end

local function equal(a, b)
  assert(type(a) == type(b), "Types differ: " .. type(a) .. " / " .. type(b))
  if type(a) ~= "table" then assert(a == b, tostring(a) .. " ~= " .. tostring(b)); return end
  for k, v in pairs(a) do equal(v, b[k]) end
  for k in pairs(b) do assert(a[k] ~= nil, "Unexpected key " .. tostring(k)) end
end

local function test(name, fn)
  local ok, err = pcall(fn)
  assert(ok, name .. ": " .. tostring(err))
  table.insert(passed, name)
  print("PASS " .. name)
end

local function layout(list, index)
  index = index or 1
  if index == #list then return { block_id = list[index] } end
  return { split = { direction = "horizontal", ratio = 0.4,
    before = { block_id = list[index] }, after = layout(list, index + 1) } }
end

local function entry(list, closed_at)
  return { closed_at = closed_at or (NOW - TTL), index = 0,
    window = { window_id = "window:old", focused_block_id = list[1],
      layers = { { kind = "tiled", layout = layout(list) } } } }
end

local function state(entries)
  return { version = 1, sessions = { [SID] = entries } }
end

local function block(id, placement)
  return { block_id = id, placement = placement or "detached",
    window_id = placement and "window:visible" or nil }
end

local function server(items)
  local s = { items = {}, calls = {}, saved = {}, closed = {}, failures = {}, live = { SID } }
  for _, item in ipairs(items or {}) do s.items[item.block_id] = copy(item) end
  function s.api(session, method, args)
    table.insert(s.calls, { session = session, method = method, args = copy(args) })
    if method == "session.list" then
      if s.list_error then error(s.list_error, 0) end
      local sessions = {}
      for _, id in ipairs(s.live) do table.insert(sessions, { session_id = id }) end
      return { sessions = sessions }
    elseif method == "session.list_blocks" then
      local result = {}
      for _, item in pairs(s.items) do table.insert(result, copy(item)) end
      return { blocks = result }
    elseif method == "block.close" then
      local id = args.block_id
      if s.failures[id] then local err = s.failures[id]; s.failures[id] = nil; error(err, 0) end
      assert(args.keep_last == true, "Missing last-visible-pane protection")
      assert(s.items[id].placement == "detached", "Attempted to close a visible/unknown pane")
      s.items[id] = nil
      table.insert(s.closed, id)
      return { block_id = id }
    end
    error("Unexpected API " .. method, 0)
  end
  s.engine = core.new{ api = s.api, save = function(value) table.insert(s.saved, copy(value)) end,
    now = function() return NOW end, token = function() return "test-token" end }
  return s
end

test("24h exact boundary", function()
  local s, data = server{ block("a") }, state{ entry{ "a" } }
  equal(s.engine.expire(data, NOW - 1), { expired_tabs = 0, closed_terminals = 0, errors = {} })
  equal(s.calls, {}); equal(s.saved, {})
  equal(s.engine.expire(data, NOW), { expired_tabs = 1, closed_terminals = 1, errors = {} })
  equal(s.closed, { "a" }); equal(data.sessions, {}); equal(s.saved[#s.saved], data)
end)

test("visible and unknown placements survive", function()
  local s = server{ block("visible", "placed"), block("unknown", "future") }
  local data = state{ entry{ "visible", "unknown" } }
  local result = s.engine.expire(data, NOW)
  equal(s.closed, {}); assert(s.items.visible and s.items.unknown)
  assert(result.expired_tabs == 1 and result.closed_terminals == 0)
end)

test("newer duplicate gets its own retention period", function()
  local recent = entry({ "shared", "new-only" }, NOW - 30)
  local data = state{ entry{ "shared", "old-only" }, recent }
  local s = server{ block("shared"), block("old-only"), block("new-only") }
  s.engine.expire(data, NOW)
  equal(s.closed, { "old-only" }); equal(data.sessions[SID], { recent })
  s.engine.expire(data, recent.closed_at + TTL)
  assert(#s.closed == 3); equal(data.sessions, {})
end)

test("failed close retains journal and retries only surviving blocks", function()
  for _, message in ipairs({ "transport unavailable", "timeout" }) do
    local s, data = server{ block("a"), block("b") }, state{ entry{ "a", "b" } }
    local original = copy(data)
    s.failures.b = message
    local result = s.engine.expire(data, NOW)
    assert(result.expired_tabs == 0 and result.closed_terminals == 1 and #result.errors == 1)
    equal(data, original); equal(s.saved, {}); equal(s.closed, { "a" })
    equal(s.engine.expire(data, NOW), { expired_tabs = 1, closed_terminals = 1, errors = {} })
    equal(s.closed, { "a", "b" }); equal(data.sessions, {})
  end
end)

test("unavailable server leaves state untouched", function()
  local s, data = server{ block("a") }, state{ entry{ "a" } }
  local original = copy(data)
  s.list_error = "Rex is not running"
  assert(not pcall(s.engine.expire, data, NOW))
  equal(data, original); equal(s.saved, {}); equal(s.closed, {})
  s.list_error = nil
  s.engine.expire(data, NOW); equal(s.closed, { "a" })
end)

test("partial restore expires detached originals only", function()
  local retained = entry{ "visible", "pending" }
  retained.restoring = { token = "partial", window_id = "window:visible",
    layers = { { pairs = { { "pending", "placeholder" } } } } }
  local data, original = state{ retained }, copy(retained)
  local s = server{ block("visible", "placed"), block("pending"), block("placeholder", "placed") }
  equal(s.engine.expire(data, NOW), { expired_tabs = 0, closed_terminals = 1, errors = {} })
  equal(s.closed, { "pending" }); equal(data.sessions[SID][1], original)
  assert(s.items.visible and s.items.placeholder)
  s.engine.expire(data, NOW); equal(s.closed, { "pending" })
end)

test("empty histories do not contact server", function()
  for _, data in ipairs({ { version = 1, sessions = {} }, state{} }) do
    local s = server{}
    s.engine.expire(data, NOW)
    equal(s.calls, {}); equal(s.saved, {})
  end
end)

test("already exited blocks prune metadata", function()
  local s, data = server{}, state{ entry{ "gone" } }
  equal(s.engine.expire(data, NOW), { expired_tabs = 1, closed_terminals = 0, errors = {} })
  equal(s.closed, {}); equal(data.sessions, {})
end)

test("exact not_found tolerated; other errors retained", function()
  local s, data = server{ block("a") }, state{ entry{ "a" } }
  s.failures.a = "stream failed (status=404 code=not_found)"
  assert(#s.engine.expire(data, NOW).errors == 0)
  equal(data.sessions, {})
  s, data = server{ block("a") }, state{ entry{ "a" } }
  s.failures.a = "binary not found"
  assert(#s.engine.expire(data, NOW).errors == 1)
  assert(data.sessions[SID])
end)

test("session filter preserves other histories", function()
  local data = state{ entry{ "a" } }
  data.sessions["session:other"] = { entry{ "b" } }
  local untouched = copy(data.sessions["session:other"])
  local s = server{ block("a"), block("b") }
  s.engine.expire(data, NOW, SID)
  equal(s.closed, { "a" }); equal(data.sessions["session:other"], untouched)
end)

test("last tab replacement precedes detachment and journal precedes mutation", function()
  local data = { version = 1, sessions = {} }
  local original = entry({ "a" }, NOW).window
  original.layers[1].blocks = { { block_id = "a" } }
  local windows, journaled, replacement = { original }, false, false
  local engine = core.new{ now = function() return NOW end,
    save = function(updated) assert(updated.sessions[SID][1].window.window_id == "window:old"); journaled = true end,
    api = function(_, method)
      if method == "session.view" then return { windows = windows, active_window_id = windows[1].window_id } end
      if method == "session.list_blocks" then return { blocks = { { block_id = "a", window_id = "window:old" } } } end
      assert(journaled, "Mutation before journal write")
      if method == "session.new_window" then
        replacement = true; table.insert(windows, { window_id = "window:new" }); return {}
      end
      if method == "session.detach_block" then
        assert(replacement, "Final tab detached without replacement"); table.remove(windows, 1); return {}
      end
      error(method)
    end }
  local result = engine.close(data, SID, "a")
  assert(result.changed and result.window_id == "window:new" and result.retained == 1)
  assert(data.sessions[SID][1].index == 0)
end)

test("restore preserves block identity and does not repeat a completed restore", function()
  local data = state{ entry({ "original" }, NOW) }
  local items = { original = block("original") }
  local made, mutations, saved = false, {}, {}
  local engine = core.new{ save = function(value) table.insert(saved, copy(value)) end,
    token = function() return "nonce" end, api = function(_, method, args)
      if method == "session.list_blocks" then
        local result = {}; for _, item in pairs(items) do table.insert(result, copy(item)) end
        return { blocks = result }
      end
      if method == "session.view" then
        if not made then return { windows = {} } end
        local placed = {}
        for _, item in pairs(items) do if item.window_id == "window:restored" then table.insert(placed, copy(item)) end end
        return { windows = { { window_id = "window:restored", layers = {
          { layer_id = "layer:tiled", blocks = placed } } } } }
      end
      table.insert(mutations, method)
      if method == "session.new_window" then
        assert(saved[#saved].sessions[SID][1].restoring.token == "nonce", "Token not journaled")
        assert(args.layout.block.label == "rex-reopen-nonce-0-original")
        made = true
        items.placeholder = { block_id = "placeholder", placement = "placed", window_id = "window:restored" }
        return { window_id = "window:restored", block_ids = { "placeholder" } }
      elseif method == "session.move_block" then
        assert(args.block_id == "original" and args.anchor_block_id == "placeholder")
        items.original.placement, items.original.window_id = "placed", "window:restored"
      elseif method == "block.close" then
        assert(args.block_id == "placeholder", "Original process was closed")
        items.placeholder = nil
      elseif method == "session.focus_block" then assert(args.block_id == "original")
      elseif method ~= "session.move_window" then error(method) end
      return {}
    end }
  local result = engine.reopen(data, SID)
  assert(result.changed and result.window_id == "window:restored" and result.remaining == 0)
  assert(items.original and not items.placeholder)
  local count = #mutations
  assert(not engine.reopen(data, SID).changed)
  assert(#mutations == count, "Second reopen repeated completed mutations")
end)

test("journal keeps empty arrays compatible with previous implementation", function()
  local data = state{ entry{ "a" } }
  data.sessions[SID][1].restoring = { token = "nonce", layers = {}, plans = {} }
  local encoded = core.encode_state(data)
  assert(encoded:find('"layers":[]', 1, true))
  assert(encoded:find('"plans":[]', 1, true))
  assert(core.encode_state(state{}):find('"session:test":[]', 1, true))
  local decoded = assert(rex.json.decode(encoded))
  equal(decoded, data)
end)

return { passed = #passed, source = "closed-tabs-core.lua", live_api_calls = 0 }
