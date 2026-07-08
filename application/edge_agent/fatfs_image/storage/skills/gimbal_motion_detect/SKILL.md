---
{
  "name": "gimbal_motion_detect",
  "description": "Use the camera and motion_detect Lua module to show a live LCD preview and draw a bounding box around detected motion.",
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
      "gimbal",
      "lcd"
    ]
  }
}
---

# Gimbal Motion Detect

Use this skill when the user wants `esp-claw` to show the camera preview on the
LCD and draw a bounding box around moving regions. The script opens the board
camera, converts frames to RGB565, displays the same centered preview style used
by `gimbal_color_detect`, and runs the standalone `motion_detect` Lua module.

Preview display follows the `gimbal_color_detect` path by default: crop a
centered `240x240` square from the board-default camera stream, flip it
vertically, and draw it centered on the `284x240` LCD.

## Default Hardware

- Camera device: from `board_manager.get_camera_paths()`
- Camera stream: board default mode from `camera.open(dev_path)`
- LCD panel: from `board_manager.get_display_lcd_params("display_lcd")`
- Runtime shape: a single async Lua job owns camera, LCD preview, and motion detection.

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
    "pixel_diff_threshold": {
      "type": "integer",
      "default": 24,
      "description": "Per-pixel luma difference threshold."
    },
    "active_pixel_percent": {
      "type": "integer",
      "default": 5,
      "description": "Minimum active-pixel percentage inside the ROI required for raw motion."
    },
    "confirm_frames": {
      "type": "integer",
      "default": 2
    },
    "hold_frames": {
      "type": "integer",
      "default": 3
    },
    "block_size": {
      "type": "integer",
      "default": 4
    },
    "block_hit_pixels": {
      "type": "integer",
      "default": 5
    },
    "box_padding": {
      "type": "integer",
      "default": 2
    },
    "box_deadband": {
      "type": "integer",
      "default": 2
    },
    "box_snap_threshold": {
      "type": "integer",
      "default": 24
    }
  }
}
```

## Tool Call Inputs

Start motion tracking:

```json
{
  "path": "{CUR_SKILL_DIR}/scripts/start_gimbal_motion_detect.lua",
  "args": {},
  "timeout_ms": 0,
  "name": "gimbal_motion_detect",
  "exclusive": "gimbal_motion_detect",
  "replace": true
}
```

Stop motion tracking:

```json
{
  "name": "gimbal_motion_detect",
  "wait_ms": 2000
}
```

## Recommended Flow

1. Activate `gimbal_motion_detect`.
2. Run `{CUR_SKILL_DIR}/scripts/start_gimbal_motion_detect.lua` with `lua_run_script_async`.
3. Use `timeout_ms: 0`, `name: "gimbal_motion_detect"`, `exclusive: "gimbal_motion_detect"`, and `replace: true`.
4. Tune `pixel_diff_threshold`, `active_pixel_percent`, and `block_hit_pixels` for sensitivity.
