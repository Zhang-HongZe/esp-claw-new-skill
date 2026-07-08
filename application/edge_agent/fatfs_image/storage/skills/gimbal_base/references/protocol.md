# Gimbal Base BLE Control Protocol

The gimbal base advertises as `esp-claw-gimbal*`. The joystick connects as a BLE
central, discovers the private control characteristic, and writes exactly five
payload bytes with GATT Write Without Response.

- Service UUID: `f7c10001-b5a3-f393-e0a9-e50e24dcca9e`
- Characteristic UUID: `f7c10002-b5a3-f393-e0a9-e50e24dcca9e`

The payload format is unchanged from the previous vendor-output report design;
there is no report ID byte in the payload.

## Joystick Report

```text
[0x01, X_low, X_high, Y_low, Y_high]
```

- X and Y use signed little-endian 16-bit HID logical values.
- ADC `0..3000` maps to HID `-32768..32767` before transmission.
- X HID `-32768..32767` maps to X angle `180..0`.
- Y HID `-32768..32767` maps to Y angle `70..10`.

## Keyboard Report

```text
[0x02, modifier, HID_keycode, pressed, 0x00]
```

- `pressed` is `1` for a key press/repeat and `0` for release.
- Left (`0x50`) or A (`0x04`) decreases the X angle.
- Right (`0x4F`) or D (`0x07`) increases the X angle.
- Up (`0x52`) or W (`0x1A`) increases the Y angle.
- Down (`0x51`) or S (`0x16`) decreases the Y angle.
- Each press/repeat moves by `key_step_degrees`, default `3` degrees.

## Servo Control

The BLE main task only unpacks incoming reports and sends X/Y target angles to
one servo worker queue. The worker owns X/Y and claw LEDC PWM handles, advances
each X/Y axis toward the latest queued target, and runs claw commands as a
non-blocking state machine:

- update period: `servo_update_ms`, default `1` ms
- maximum angle step per update: `servo_max_step_degrees`, default `2`
- when Y is greater than `y_top_trigger_angle` (`60` by default), the main task queues `claw,double`
- `claw,double`: open, wait `double_clamp_pulse_ms` (`150` ms by default), close, wait, then repeat once
- when Y drops below `y_top_release_angle` (`55` by default), the latch resets and the main task queues `claw,close`
