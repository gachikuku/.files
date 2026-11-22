-- Yazi 26.9.1: fit and center native image formats in the preview area.
local M = {}

function M:peek(job)
  local source = Url(job.file.path)
  local info = ya.image_info(source)
  local cw, ch = rt.term.cell_size()
  if not info or not cw or not ch or cw <= 0 or ch <= 0 then
    return require("image"):peek(job)
  end
  local area = job.area
  if area.w == 0 or area.h == 0 then return end
  local width, height = info.w, info.h
  if info.ori and info.ori >= 5 and info.ori <= 8 then width, height = info.h, info.w end
  if width <= 0 or height <= 0 then return require("image"):peek(job) end

  local maxw = math.max(1, math.min(math.floor(area.w * cw), rt.preview.max_width))
  local maxh = math.max(1, math.min(math.floor(area.h * ch), rt.preview.max_height))
  local scale = math.min(maxw / width, maxh / height)
  local url = source
  if scale > 1 then
    local base = ya.file_cache(job)
    if not base then return require("image"):peek(job) end
    local cache = Url(tostring(base) .. string.format("-fit-%dx%d.png", maxw, maxh))
    if not fs.cha(cache) then
      -- Yazi's Nix wrapper supplies ImageMagick. Keep filenames as literal
      -- argv values and reuse the preset's resource limits.
      local status, err = require("magick").with_limit():arg {
        "-define", "filename:literal=true", "-define", "image:frames=0",
        tostring(job.file.path), "-auto-orient", "-strip", "-filter", "triangle",
        "-resize", string.format("%dx%d", maxw, maxh), "PNG:" .. tostring(cache),
      }:status()
      if not status or not status.success then
        ya.err("fit-image: resize failed", err or (status and status.code))
        return require("image"):peek(job)
      end
    end
    url = cache
  end

  -- Center to the nearest terminal cell without cropping either dimension.
  local cols = math.min(area.w, math.max(1, math.ceil(width * scale / cw)))
  local rows = math.min(area.h, math.max(1, math.ceil(height * scale / ch)))
  local rect = ui.Rect {
    x = area.x + math.floor((area.w - cols) / 2),
    y = area.y + math.floor((area.h - rows) / 2),
    w = cols, h = rows,
  }
  local _, err = ya.image_show(url, rect)
  ya.preview_widget(job, err)
end

function M:seek() end
return M
