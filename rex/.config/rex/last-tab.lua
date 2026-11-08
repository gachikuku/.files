-- The background tracker is the sole writer; actions only read its snapshots.
local state_path = os.getenv("HOME") .. "/.config/rex/tab-history-state.json"

local function read_history(session_id)
  local file = io.open(state_path, "r")
  if not file then return nil end
  local ok, state = pcall(rex.json.decode, file:read("*a"))
  file:close()
  if not ok or type(state) ~= "table" or type(state.sessions) ~= "table" then return nil end
  return state.sessions[session_id]
end

rex.action{
  name = "last_visited_tab",
  title = "Return to Last Visited Tab",
  description = "Toggle between the two most recently visited tabs in this session.",
  category = "Tab",
  run = function(ctx)
    local view, history, ready
    -- Let focus events already in flight reach the tracker before choosing.
    for attempt = 1, 11 do
      local err
      view, err = rex.session.view{ session_id = ctx.session_id }
      if not view then error(err) end
      history = read_history(ctx.session_id)
      ready = history and (history.revision or -1) >= view.revision
        and history.order and history.order[1] == view.active_window_id
      if ready then break end
      if attempt < 11 then rex.exec({ "/bin/sleep", "0.02" }, { timeout = 1 }) end
    end
    if not ready then
      return { switched = false, reason = "Tab history is not ready yet." }
    end
    local live = {}
    for _, window in ipairs(view.windows or {}) do live[window.window_id] = true end
    for _, window_id in ipairs(history.order or {}) do
      if live[window_id] and window_id ~= view.active_window_id then
        if ctx.client_id then
          -- Selecting the server window alone does not change the app's tab.
          rex.client.queue("session.select", {
            session_id = ctx.session_id, window_id = window_id,
          })
        else
          local result, focus_err = rex.session.focus_window{
            session_id = ctx.session_id, window_id = window_id,
          }
          if not result then error(focus_err) end
        end
        return { switched = true, window_id = window_id }
      end
    end
    return { switched = false, reason = "No previously visited tab remains open." }
  end,
}
