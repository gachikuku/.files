local module = dofile(os.getenv("HOME") .. "/.files/rex/.config/rex/clicked-pane.lua")
local function block(id)
  return { block_id = id, creator_name = "com.superlogical.terminal", host_id = "local" }
end
local left, right, bottom, floating = block("left"), block("right"), block("bottom"), block("floating")
local function leaf(id, rect) return { block_id = id, rect = rect } end
local function tiled(layout, blocks) return { kind = "tiled", layout = layout, blocks = blocks } end
local function view(layers, zoom)
  return { active_window_id = "active", windows = {
    { window_id = "other", layers = { tiled(leaf("wrong", {0,0,1,1}), {block("wrong")}) } },
    { window_id = "active", focused_block_id = "right", zoomed_block_id = zoom, layers = layers },
  } }
end
local function expect(snapshot, pane, id, error_text)
  local result, err = module.find(snapshot, pane)
  assert((result and result.block_id) == id, tostring(err or (result and result.block_id)))
  if error_text then assert(err and err:find(error_text, 1, true), tostring(err)) end
  return result
end
local split = { split = {
  before = leaf("left", {0,0,0.5,1}), after = leaf("right", {0.5,0,0.5,1}),
} }
local base = view({ tiled(split, {left,right}) })
assert(expect(base, {x=0,y=0,w=0.5,h=1}, "left") == left)
expect(base, {x=0.5,y=0,w=0.5,h=1}, "right")
expect(base, {x=0.006,y=0.008,w=0.488,h=0.984}, "left")
expect(base, {x=0.03,y=0,w=0.47,h=1}, nil, "does not match")
expect(base, {x=0,y=0,w=1,h=1}, nil, "does not match")
local nested = { split = { before = split, after = leaf("bottom", {0,0.5,1,0.5}) } }
nested.split.before = { split = {
  before = leaf("left", {0,0,0.5,0.5}), after = leaf("right", {0.5,0,0.5,0.5}),
} }
expect(view({tiled(nested,{left,right,bottom})}), {x=0,y=0.5,w=1,h=0.5}, "bottom")
expect(view({tiled(split,{left,right})}, "left"), {x=0.005,y=0.005,w=0.99,h=0.99}, "left")
expect(view({tiled(split,{left,right})}, "left"), {x=0,y=0,w=0.5,h=1}, nil, "zoomed")
local float = {kind="floating",layout=leaf("floating",{0.2,0.2,0.5,0.5}),blocks={floating}}
expect(view({tiled(split,{left,right}),float}), {x=0,y=0,w=0.5,h=1}, nil, "floating")
float.state = "minimized"
expect(view({tiled(split,{left,right}),float}), {x=0,y=0,w=0.5,h=1}, "left")
local duplicate = {split={before=leaf("left",{0,0,1,1}),after=leaf("right",{0,0,1,1})}}
expect(view({tiled(duplicate,{left,right})}), {x=0,y=0,w=1,h=1}, nil, "more than one")
local near = {split={before=leaf("left",{0,0,0.99,1}),after=leaf("right",{0,0,1,1})}}
expect(view({tiled(near,{left,right})}), {x=0,y=0,w=1,h=1}, "right")
expect(base, {x=0,y=0,w=0,h=1}, nil, "valid normalized")
expect({windows={}}, {x=0,y=0,w=1,h=1}, nil, "no active")
print("PASS: 14 clicked-pane cases (unfocused splits, tolerance, nested layout, zoom, floating, ambiguity)")
