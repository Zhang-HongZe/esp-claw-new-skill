---
{
  "name": "gimbal_color_detect",
  "description": "Use the camera and vision Lua modules to detect a green target, show the camera preview on the LCD, draw a bounding box, and drive X/Y gimbal servos toward the target center.",
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
      "color-detect",
      "gimbal",
      "servo",
      "lcd"
    ]
  }
}
---

# Gimbal Color Detect

Use this skill when the user wants `esp-claw` to use the camera as a visual
servo target tracker. The script opens the board camera, displays frames on the
LCD, detects a green object through the `color_detect` vision Lua module, draws
the detection box, and directly drives X/Y servos from the same Lua job.

The default detection target is green. Tune the HSV-like thresholds through
`green_h_min`, `green_h_max`, `green_s_min`, and `green_v_min` if the lighting
or target color changes.

Preview display follows the `esp-hello-new/examples/gimbal_base` camera path by
default: crop a centered `240x240` square from the board-default camera stream,
flip it vertically, and draw it centered on the `284x240` LCD.

## Default Hardware

- Camera device: from `board_manager.get_camera_paths()`
- Camera stream: board default mode from `camera.open(dev_path)`
- LCD panel: from `board_manager.get_display_lcd_params("display_lcd")`
- X servo GPIO: `4`
- Y servo GPIO: `5`
- PWM driver: `ledc`, `50 Hz`, `500 us .. 2500 us`
- X angle range: `0 .. 180`, initial `90`
- Y angle range: `10 .. 70`, initial `50`
- Runtime shape: a single async Lua job owns camera, LCD, color detection, and X/Y LEDC servos.

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
      "default": 10,
      "description": "Print average get/convert/detect/display/loop timing every N frames. Set 0 to disable."
    },
    "display_crop_size": {
      "type": "integer",
      "default": 240,
      "description": "Centered square crop size before drawing to the LCD."
    },
    "display_flip_y": {
      "type": "boolean",
      "default": true,
      "description": "Flip the cropped preview vertically to match the gimbal_base example orientation."
    },
    "detect_stride": {
      "type": "integer",
      "default": 4
    },
    "detect_min_pixels": {
      "type": "integer",
      "default": 20
    },
    "green_h_min": {
      "type": "integer",
      "default": 50
    },
    "green_h_max": {
      "type": "integer",
      "default": 88
    },
    "green_s_min": {
      "type": "number",
      "default": 0.31
    },
    "green_v_min": {
      "type": "number",
      "default": 0.2
    },
    "deadzone_px": {
      "type": "integer",
      "default": 12
    },
    "x_gain": {
      "type": "number",
      "default": 0.035
    },
    "y_gain": {
      "type": "number",
      "default": -0.035
    },
    "max_track_step_degrees": {
      "type": "number",
      "default": 2
    },
    "x_gpio": {
      "type": "integer",
      "default": 4
    },
    "y_gpio": {
      "type": "integer",
      "default": 5
    },
    "servo_max_step_degrees": {
      "type": "number",
      "default": 2
    }
  }
}
```

## Tool Call Inputs

Start color tracking:

```json
{
  "path": "{CUR_SKILL_DIR}/scripts/start_gimbal_color_detect.lua",
  "args": {},
  "timeout_ms": 0,
  "name": "gimbal_color_detect",
  "exclusive": "gimbal_color_detect",
  "replace": true
}
```

Stop color tracking:

```json
{
  "name": "gimbal_color_detect",
  "wait_ms": 2000
}
```

## Recommended Flow

1. Activate `board_hardware_info` first when the user wants pin validation.
2. Activate `gimbal_color_detect`.
3. Run `{CUR_SKILL_DIR}/scripts/start_gimbal_color_detect.lua` with `lua_run_script_async`.
4. Use `timeout_ms: 0`, `name: "gimbal_color_detect"`, `exclusive: "gimbal_color_detect"`, and `replace: true`.
5. Tune `x_gain` / `y_gain` signs if servo direction is reversed on a specific mount.
