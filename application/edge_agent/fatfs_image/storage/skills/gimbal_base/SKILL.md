---
{
  "name": "gimbal_base",
  "description": "Start the gimbal base as a BLE HID device, bind a joystick, and control the X/Y and claw servos. Requires BLE HID, thread, and LEDC Lua modules.",
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
      "bluetooth",
      "hid",
      "gimbal",
      "servo",
      "gamepad"
    ]
  }
}
---

# Gimbal Base

Use this skill when the user wants `esp-claw` to advertise as a BLE HID gimbal
base, bind a joystick, and drive X/Y and claw servos through the `ledc` module.

Activating the skill does not alter `activate_skill` or auto-run firmware code.
After activation, run exactly one async Lua script. The script starts BLE HID
advertising, waits for bonding, reports success or timeout to the IM chat that
started it, then receives HID output reports until stopped.

If the start script returns an error, report it directly. Do not retry with
changed pins, BLE names, protocol bytes, or PWM timing unless the user asks.

## BLE Control Protocol

The gimbal advertises as `esp-claw-gimbal*` and accepts 5-byte control packets
through a private BLE GATT control characteristic:

- Service UUID: `f7c10001-b5a3-f393-e0a9-e50e24dcca9e`
- Characteristic UUID: `f7c10002-b5a3-f393-e0a9-e50e24dcca9e`
- Payload length: exactly `5` bytes
- Joystick: `[0x01, X_low, X_high, Y_low, Y_high]`; X/Y are little-endian signed 16-bit HID axes in `-32768..32767`
- Keyboard: `[0x02, modifier, HID_keycode, pressed, 0x00]`
- Supported keys: Left/Right or A/D move X; Up/Down or W/S move Y

Read `{CUR_SKILL_DIR}/references/protocol.md` for the byte layout and mapping.

## Default Hardware

- X servo GPIO: `4`
- Y servo GPIO: `5`
- Left claw GPIO: `12`
- Right claw GPIO: `28`
- PWM driver: `ledc`, `50 Hz`, `500 us .. 2500 us`
- X angle range: `0 .. 180`, initial `90`
- Y angle range: `10 .. 70`, initial `50`
- Servo control worker: one worker receives X/Y targets and claw commands from the BLE main task, then drives all four LEDC servos.

## Start Script Args Schema

```json
{
  "type": "object",
  "properties": {
    "device_name": {
      "type": "string",
      "default": "esp-claw-gimbal",
      "minLength": 1,
      "maxLength": 29
    },
    "bind_timeout_ms": {
      "type": "integer",
      "default": 60000,
      "minimum": 1000
    },
    "poll_ms": {
      "type": "integer",
      "default": 50,
      "minimum": 1
    },
    "key_step_degrees": {
      "type": "integer",
      "default": 3,
      "minimum": 1,
      "maximum": 30
    },
    "servo_max_step_degrees": {
      "type": "integer",
      "default": 2,
      "minimum": 1,
      "maximum": 30
    },
    "servo_update_ms": {
      "type": "integer",
      "default": 1,
      "minimum": 1
    },
    "xy_servo_worker_path": {
      "type": "string",
      "default": "<DATA>/skills/gimbal_base/scripts/xy_servo_worker.lua"
    },
    "x_gpio": {
      "type": "integer",
      "default": 4,
      "minimum": 0
    },
    "y_gpio": {
      "type": "integer",
      "default": 5,
      "minimum": 0
    },
    "left_claw_gpio": {
      "type": "integer",
      "default": 12,
      "minimum": 0
    },
    "right_claw_gpio": {
      "type": "integer",
      "default": 28,
      "minimum": 0
    },
    "claw_closed_angle": {
      "type": "integer",
      "default": 90,
      "minimum": 0,
      "maximum": 180
    },
    "left_claw_open_angle": {
      "type": "integer",
      "default": 60,
      "minimum": 0,
      "maximum": 180
    },
    "right_claw_open_angle": {
      "type": "integer",
      "default": 120,
      "minimum": 0,
      "maximum": 180
    },
    "double_clamp_pulse_ms": {
      "type": "integer",
      "default": 150,
      "minimum": 0
    },
    "y_top_trigger_angle": {
      "type": "integer",
      "default": 60,
      "minimum": 0,
      "maximum": 180
    },
    "y_top_release_angle": {
      "type": "integer",
      "default": 55,
      "minimum": 0,
      "maximum": 180
    }
  }
}
```

## Tool Call Inputs

Start the receiver:

```json
{
  "path": "{CUR_SKILL_DIR}/scripts/start_gimbal_base.lua",
  "args": {},
  "timeout_ms": 0,
  "name": "gimbal_base",
  "exclusive": "gimbal_base",
  "replace": true
}
```

Stop the receiver:

```json
{
  "name": "gimbal_base",
  "wait_ms": 2000
}
```

## Recommended Flow

1. Activate `board_hardware_info` first when the user wants pin validation.
2. Activate `gimbal_base`.
3. Run `{CUR_SKILL_DIR}/scripts/start_gimbal_base.lua` with `lua_run_script_async`.
4. Use `timeout_ms: 0`, `name: "gimbal_base"`, `exclusive: "gimbal_base"`, and `replace: true`.
5. Let the script publish binding success or timeout to the originating IM chat.
6. Stop or restart it with `lua_stop_async_job` and `name: "gimbal_base"`.
