# Lua Motion Detect

`motion_detect` detects local motion in consecutive `image.frame` values. The
algorithm is ported from `esp-halo-internal/example/lcd_ai_detect`: it compares
RGB565 luma against the previous frame inside an ROI, groups changed pixels into
blocks, pads the resulting box, and applies confirm/hold state to produce a
stable alert.

## Usage

```lua
local camera = require("camera")
local image = require("image")
local motion_detect = require("motion_detect")

local detector = motion_detect.new({
    roi = { x = 0, y = 40, width = 240, height = 240 },
    pixel_diff_threshold = 24,
    active_pixel_percent = 5,
})

local frame <close> = camera.get_frame(3000)
local rgb565 <close> = image.convert(frame, image.RGB565)
local result = detector:detect(rgb565)

if result.alert_active and result.box then
    print("motion box", result.box.left, result.box.top, result.box.right, result.box.bottom)
end
```

The first `detect()` call seeds the previous-frame buffer and returns
`has_previous = false`; subsequent calls return comparisons.

## API

### `motion_detect.new(opts) -> detector`

Creates a detector object. `opts` is optional.

### `detector:detect(frame[, opts]) -> result`

Runs detection on an `image.frame`. The frame is requested as RGB565 internally.
`opts` can override detector options for this and following calls; changing ROI
or block size reallocates buffers and resets previous-frame state.

### `detector:reset()`

Clears previous-frame and alert state.

### `detector:close()`

Releases buffers early. The object also releases buffers when garbage-collected.

### `motion_detect.detect(frame[, opts]) -> result`

Convenience singleton detector for simple scripts.

### `motion_detect.reset()`

Resets the singleton detector.

## Options

- `roi`: `{ x, y, width, height }`; default is the whole frame. Flat fields
  `roi_x`, `roi_y`, `roi_width`, and `roi_height` are also accepted.
- `pixel_diff_threshold`: luma difference threshold, default `24`.
- `active_pixel_percent`: percentage of active ROI pixels required for raw
  detection, default `5`.
- `confirm_frames`: consecutive positive frames needed before `alert_active`,
  default `2`.
- `hold_frames`: frames to keep alert active after raw detection clears,
  default `3`.
- `block_size`: edge length for motion blocks, default `4`.
- `block_hit_pixels`: changed pixels needed to mark one block active,
  default `5`.
- `box_padding`: pixels added around the raw active block box, default `2`.
- `box_deadband`: ignore smoothed box edge changes up to this size, default `2`.
- `box_snap_threshold`: snap box edges immediately for larger changes,
  default `24`.

## Result

The result table contains:

- `has_previous`: false for the first seeding frame.
- `detected`: raw motion decision for the current frame.
- `alert_active`: confirm/hold state output.
- `event`: `"none"`, `"activated"`, or `"cleared"`.
- `active_pixels`, `threshold_pixels`.
- `positive_frames`, `hold_frames`.
- `roi_x`, `roi_y`, `roi_width`, `roi_height`.
- `raw_box`: raw detection box when present.
- `box`: smoothed display box while available.
