-- Match a clicked Accessibility terminal frame to a Rex layout snapshot.
local M = {}
local tolerance, tie_epsilon = 0.025, 0.000001

local function number(value)
  return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function rectangle(x, y, w, h)
  return number(x) and number(y) and number(w) and number(h) and w > 0 and h > 0
end

local function error_between(pane, rect)
  if type(rect) ~= "table" or not rectangle(rect[1], rect[2], rect[3], rect[4]) then
    return math.huge
  end
  return math.max(math.abs(pane.x - rect[1]), math.abs(pane.y - rect[2]),
    math.abs(pane.x + pane.w - rect[1] - rect[3]),
    math.abs(pane.y + pane.h - rect[2] - rect[4]))
end

function M.find(view, pane)
  if type(pane) ~= "table" or not rectangle(pane.x, pane.y, pane.w, pane.h) then
    return nil, "The clicked pane has no valid normalized frame."
  end
  if type(view) ~= "table" or not view.active_window_id then
    return nil, "The Rex session has no active tab."
  end
  local window
  for _, candidate in ipairs(view.windows or {}) do
    if candidate.window_id == view.active_window_id then window = candidate; break end
  end
  if not window then return nil, "The active Rex tab is missing from its layout." end

  local blocks = {}
  for _, layer in ipairs(window.layers or {}) do
    if layer.state ~= "minimized" then
      for _, block in ipairs(layer.blocks or {}) do blocks[block.block_id] = block end
    end
  end
  if window.zoomed_block_id then
    local block = blocks[window.zoomed_block_id]
    if block and error_between(pane, { 0, 0, 1, 1 }) <= tolerance then return block end
    return nil, "The clicked pane does not match the zoomed Rex pane."
  end

  for _, layer in ipairs(window.layers or {}) do
    if layer.kind ~= "tiled" and layer.state ~= "minimized" and layer.layout then
      return nil, "Relative paths in tabs with visible floating panes are not supported yet."
    end
  end

  local best, score, tied = nil, math.huge, false
  local function visit(node)
    if type(node) ~= "table" then return end
    if node.block_id then
      local distance = error_between(pane, node.rect)
      if distance <= tolerance and blocks[node.block_id] then
        if distance < score - tie_epsilon then
          best, score, tied = blocks[node.block_id], distance, false
        elseif math.abs(distance - score) <= tie_epsilon and best.block_id ~= node.block_id then
          tied = true
        end
      end
    elseif node.split then
      visit(node.split.before)
      visit(node.split.after)
    end
  end
  for _, layer in ipairs(window.layers or {}) do
    if layer.kind == "tiled" and layer.state ~= "minimized" then visit(layer.layout) end
  end
  if tied then return nil, "The clicked frame matches more than one Rex pane." end
  if not best then return nil, "The clicked frame does not match a Rex pane." end
  return best
end

return M
