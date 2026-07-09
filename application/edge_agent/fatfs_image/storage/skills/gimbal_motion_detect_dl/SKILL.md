---
{
  "name": "gimbal_motion_detect_dl",
  "description": "Use the camera and lua_module_vision lightweight motion detector to show a live LCD preview and indicate frame-level motion.",
  "metadata": {
    "cap_groups": [
      "cap_lua"
    ],
    "manage_mode": "readonly",
    "category": [
      "utility"
    ],
    "peripherals": [],
    "tags": [
      "camera",
      "vision",
      "motion-detect",
      "lcd"
    ]
  }
}
---

# Gimbal Motion Detect DL

Use this skill when the user wants a lightweight motion detector implemented
through `lua_module_vision`. The script opens the board camera, converts frames
to RGB565 for display, shows the same centered preview style used by
`gimbal_color_detect`, and calls the vision module's `vision_motion_detect`
Lua module to compare each frame with the previous frame.

This detector reports frame-level motion statistics (`moving_ratio`,
`moving_points`, `sample_points`, `moved`). It does not compute a motion bounding
box. When motion is detected, the script draws a yellow border around the preview
ROI; otherwise it draws a green border.

Preview display follows the `gimbal_color_detect` path by default: crop a
centered `240x240` square from the board-default camera stream, flip it
vertically, and draw it centered on the `284x240` LCD.

## Default Hardware

- Camera device: from `board_manager.get_camera_paths()`
- Camera stream: board default mode from `camera.open(dev_path)`
- LCD panel: from `board_manager.get_display_lcd_params("display_lcd")`
- Runtime shape: a single async Lua job owns camera, LCD preview, and lightweight vision motion detection.

## Start Script Args Schema

```json
{
  "type": "object",
  "properties": {
    "run_seconds": {
      "type": "integer",
      "default": 0,
      "description": "0 means run until the async Lua job is stopped."
    },
    "frame_interval_ms": {
      "type": "integer",
      "default": 0,
      "description": "Extra delay after each frame. Keep 0 for maximum camera/display throughput."
    },
    "display_every_n": {
      "type": "integer",
      "default": 1
    },
    "perf_log_every_n": {
      "type": "integer",
      "default": 30,
      "description": "Print average get/convert/detect/display/loop timing every N frames. Set 0 to disable."
    },
    "display_crop_size": {
      "type": "integer",
      "default": 240,
      "description": "Centered square crop size before drawing to the LCD."
    },
    "display_flip_y": {
      "type": "boolean",
      "default": true
    },
    "detect_stride": {
      "type": "integer",
      "default": 4,
      "description": "Sampling stride used by vision_motion_detect."
    },
    "pixel_threshold": {
      "type": "number",
      "default": 0.039,
      "description": "Per-sample gray-value difference threshold normalized to 0..1."
    },
    "moving_threshold": {
      "type": "number",
      "default": 0.03,
      "description": "Moving sample ratio required to set moved=true."
    }
  }
}
```

## Tool Call Inputs

Start lightweight vision motion detection:

```json
{
  "path": "{CUR_SKILL_DIR}/scripts/start_gimbal_motion_detect_dl.lua",
  "args": {},
  "timeout_ms": 0,
  "name": "gimbal_motion_detect_dl",
  "exclusive": "gimbal_motion_detect_dl",
  "replace": true
}
```

Stop lightweight vision motion detection:

```json
{
  "name": "gimbal_motion_detect_dl",
  "wait_ms": 2000
}
```

## Recommended Flow

1. Activate `gimbal_motion_detect_dl`.
2. Run `{CUR_SKILL_DIR}/scripts/start_gimbal_motion_detect_dl.lua` with `lua_run_script_async`.
3. Use `timeout_ms: 0`, `name: "gimbal_motion_detect_dl"`, `exclusive: "gimbal_motion_detect_dl"`, and `replace: true`.
4. Tune `pixel_threshold` and `moving_threshold` for sensitivity.
