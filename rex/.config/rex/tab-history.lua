-- Run under launchd: rex --autostart=false do tab-history.lua --all --fail-fast
local path = os.getenv("HOME") .. "/.config/rex/tab-history-state.json"
local state = { version = 1, sessions = {} }
local file = io.open(path, "r")
if file then
  local ok, saved = pcall(rex.json.decode, file:read("*a"))
  file:close()
  if ok and type(saved) == "table" and saved.version == 1
      and type(saved.sessions) == "table" then state = saved end
end

local function save()
  local out = assert(io.open(path .. ".tmp", "w"))
  out:write(rex.json.encode(state))
  out:close()
  assert(os.rename(path .. ".tmp", path))
end

local function entry(session_id)
  if not state.sessions[session_id] then
    state.sessions[session_id] = { order = {}, revision = -1 }
  end
  return state.sessions[session_id]
end

local function remember(session_id, window_id)
  if not session_id or not window_id then return end
  local history = entry(session_id)
  if history.order[1] == window_id then return end
  local order = { window_id }
  for _, old in ipairs(history.order) do
    if old ~= window_id and #order < 64 then order[#order + 1] = old end
  end
  history.order = order
  save()
end

local function handle_reconcile_error(session_id, err)
  -- Rex returns API failures as strings ending in HTTP status and error code.
  -- A session can disappear after listing it or receiving session_created.
  if type(err) == "string"
      and err:match("%(status=404 code=session_not_found%)$") then
    state.sessions[session_id] = nil
    save()
    return
  end
  error(err)
end

local function reconcile(session_id)
  local attached, err = rex.session.attach{ session_id = session_id }
  if not attached then return handle_reconcile_error(session_id, err) end
  local view, view_err = rex.session.view{ session_id = session_id }
  if not view then return handle_reconcile_error(session_id, view_err) end
  local history = entry(session_id)
  local live, order = {}, {}
  for _, window in ipairs(view.windows or {}) do live[window.window_id] = true end
  for _, window_id in ipairs(history.order) do
    if live[window_id] then order[#order + 1] = window_id end
  end
  history.order = order
  history.revision = view.revision
  remember(session_id, view.active_window_id)
  save()
end

rex.on("active_window_changed", function(ctx, ev)
  remember(ev.session_id or ctx.session_id, ev.window_id)
end)

rex.on("session_view_changed", function(ctx, ev)
  local history = entry(ev.session_id or ctx.session_id)
  history.revision = math.max(history.revision or -1, ev.revision or -1)
  save()
end)

rex.on("window_closed", function(ctx, ev)
  local history = entry(ev.session_id or ctx.session_id)
  local order = {}
  for _, window_id in ipairs(history.order) do
    if window_id ~= ev.window_id then order[#order + 1] = window_id end
  end
  history.order = order
  save()
end)

rex.on("session_created", function(_, ev)
  if ev.session and ev.session.session_id then reconcile(ev.session.session_id) end
end)

rex.on("session_destroyed", function(_, ev)
  state.sessions[ev.session_id] = nil
  save()
end)

local sessions, err = rex.call("session.list", {})
if not sessions then error(err) end
local live_sessions = {}
for _, session in ipairs(sessions.sessions or {}) do
  live_sessions[session.session_id] = true
  reconcile(session.session_id)
end
for session_id in pairs(state.sessions) do
  if not live_sessions[session_id] then state.sessions[session_id] = nil end
end
save()
