-- Give the image all terminal rows; Rex's tab title identifies the file.
function Root:build()
  self._children = {
    Backdrop:new(self._area),
    Tab:new(self._area, cx.active),
    Modal:new(self._area),
  }
end
