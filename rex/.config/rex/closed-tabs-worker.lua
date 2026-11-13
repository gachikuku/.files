-- Invoked only while /usr/bin/lockf holds closed-tabs.lock. No handlers: exits.
local root = os.getenv("HOME") .. "/.config/rex/"
local core = dofile(root .. "closed-tabs-core.lua")
local args = rex.args or {}
local path = args.state_path or (root .. "closed-tabs-state.json")
local operation = args.operation
local session = args.session_id
assert(operation == "close" or operation == "reopen" or operation == "expire", "Unknown retained-tab operation.")
assert(operation == "expire" or (session and session ~= ""), "A session is required for close/reopen.")

local state = core.read_state(path)
local engine = core.new{ save = function(updated) core.write_state(path, updated) end }
local expired = engine.expire(state, nil, session)
if operation == "expire" then
  if #expired.errors > 0 then error(table.concat(expired.errors, "\n"), 0) end
  return expired
end
if #expired.errors > 0 then error("Expiry cleanup failed; please retry. " .. expired.errors[1], 0) end
if operation == "close" then return engine.close(state, session, args.block_id) end
return engine.reopen(state, session)
