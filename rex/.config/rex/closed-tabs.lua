-- Browser-style close/reopen, retaining the same terminal processes.
local root = os.getenv("HOME") .. "/.config/rex/"
local cli = "/Applications/Rex Beta.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"
local copy_mode = require("copy-mode")

local function perform(operation, ctx)
  if operation == "close" then
    local overlay = copy_mode.dismiss_if_active(ctx)
    if overlay.closed then return overlay end
  end
  -- Kernel flock coordinates actions and expiry, including during migration.
  -- One local Lua worker uses direct APIs over a single Rex connection.
  local result, err = rex.exec({ "/usr/bin/lockf", "-k", "-s", "-t", "0",
    root .. "closed-tabs.lock", cli, "--autostart=false", "do",
    root .. "closed-tabs-worker.lua", "--all", "--json",
    "operation=" .. operation, "session_id=" .. ctx.session_id,
    "block_id=" .. (ctx.block_id or "") }, { timeout = 28 })
  if not result then error(err) end
  if not result.ok then
    if result.code == 75 then error("Another tab operation is running; please retry.", 0) end
    error(result.stderr ~= "" and result.stderr or "Retained-tab operation failed.", 0)
  end
  local outcome, decode_err = rex.json.decode(result.stdout)
  if not outcome then error(decode_err, 0) end
  if outcome.changed and outcome.window_id and ctx.client_id then
    rex.client.queue("session.select", {
      session_id = outcome.session_id, window_id = outcome.window_id,
    })
  end
  return outcome
end

rex.action{
  name = "retain_closed_tab",
  title = "Close Tab (Keep for Reopening)",
  description = "Keep the closed tab available for Cmd+Shift+T for 24 hours.",
  category = "Tab",
  run = function(ctx) return perform("close", ctx) end,
}

rex.action{
  name = "reopen_closed_tab",
  title = "Reopen Closed Tab",
  description = "Bring back the most recent tab closed within the last 24 hours.",
  category = "Tab",
  run = function(ctx) return perform("reopen", ctx) end,
}
