-- Exit-only worker: capture/opening never starts another Rex process.
local snapshot = dofile(os.getenv("HOME") .. "/.config/rex/copy-snapshot.lua")
local directory = (rex.args or {}).directory
assert(snapshot.valid_directory(directory), "Invalid copy snapshot path.")
local context
-- An immediate q can race new_layer's metadata publication. Wait only on exit.
for _ = 1, 100 do
  context = snapshot.context(directory)
  if not context or context.overlay then break end
  rex.sleep(0.01)
end
if not context then return { cleaned = false } end
local ok, err = pcall(function()
  local attached = rex.session.attach{ session_id = context.session }
  if attached then snapshot.restore(context) end
end)
snapshot.clean(directory, context)
if not ok then error(err) end
return { cleaned = true }
