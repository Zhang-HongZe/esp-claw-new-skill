---
{
  "name": "gimbal_base",
  "description": "Run a simplified ESP-NOW gimbal receiver from Lua and drive four servos from a 3-byte gamepad packet. Requires Wi-Fi to already be initialized and started.",
  "metadata": {
    "cap_groups": [
      "cap_lua"
    ],
    "manage_mode": "readonly",
    "tags": [
      "esp-now",
      "gimbal",
      "servo",
      "gamepad"
    ]
  }
}
---

# Gimbal Base

Use this skill when the user wants `esp-claw` to receive simplified ESP-NOW
gamepad packets and drive the gimbal/claw servos from Lua with the `ledc`
module.

Activating this skill does not auto-start the receiver. After activation, run
exactly one async Lua script and keep it running until the user asks to stop.

Wi-Fi must already be initialized and running on the matching channel before
starting this skill.

If the device is based on `ESP32C5`, 5 GHz Wi-Fi channels are supported. The
default `channel: 36` is a valid 5 GHz example as long as both ESP-NOW peers
are using the same channel.

If the start script returns an error, report that error directly to the user.
Do not retry with changed pins, protocol, or PWM timing unless the user asks.

## Packet Format

The receiver only accepts a 3-byte packet:

```text
[0x01, X_percent, Y_percent]
```

- Byte 0: `0x01` (`ADC_VALUE`)
- Byte 1: `X` percent as an integer `0..100`
- Byte 2: `Y` percent as an integer `0..100`

Any other packet length or header is ignored.

## Default Hardware

- X servo GPIO: `4`
- Y servo GPIO: `5`
- Left claw GPIO: `12`
- Right claw GPIO: `28`
- PWM driver: `ledc`
- PWM frequency: `50 Hz`
- Pulse width range: `500 us .. 2500 us`
- X angle range: `0 .. 180`
- Y angle range: `10 .. 70`
- Initial X angle: `90`
- Initial Y angle: `50`

## Start Script Args Schema

```json
{
  "type": "object",
  "properties": {
    "pmk": {
      "type": "string",
      "default": "pmk1234567890123"
    },
    "peer_mac": {
      "type": "string",
      "default": "ff:ff:ff:ff:ff:ff"
    },
    "channel": {
      "type": "integer",
      "default": 36,
      "minimum": 0
    },
    "ifidx": {
      "type": "string",
      "default": "sta"
    },
    "poll_ms": {
      "type": "integer",
      "default": 50,
      "minimum": 0
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

Start the receiver with overridden pins:

```json
{
  "path": "{CUR_SKILL_DIR}/scripts/start_gimbal_base.lua",
  "args": {
    "x_gpio": 4,
    "y_gpio": 5,
    "left_claw_gpio": 12,
    "right_claw_gpio": 28,
    "channel": 36
  },
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

1. Activate `board_hardware_info` first if the user wants pin validation against
   the current board.
2. Activate `gimbal_base`.
3. Run `{CUR_SKILL_DIR}/scripts/start_gimbal_base.lua` with
   `lua_run_script_async`.
4. Use `timeout_ms: 0`, `name: "gimbal_base"`, `exclusive: "gimbal_base"`,
   and `replace: true` so only one listener owns the servos.
5. When the user asks to stop or restart the receiver, call
   `lua_stop_async_job` for `name: "gimbal_base"`.
6. Report success or the exact runtime error directly to the user.
