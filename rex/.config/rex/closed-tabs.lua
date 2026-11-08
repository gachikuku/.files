-- Browser-style close/reopen, retaining the same terminal processes.
local helper = os.getenv("HOME") .. "/.config/rex/closed-tabs.py"

local function perform(operation, ctx)
  local result, err = rex.exec({ "/usr/bin/python3", helper, operation,
    ctx.session_id, ctx.block_id or "" }, { timeout = 30 })
  if not result then error(err) end
  if not result.ok then error(result.stderr) end
  local outcome = rex.json.decode(result.stdout)
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
