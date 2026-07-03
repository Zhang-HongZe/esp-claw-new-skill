# Gimbal Base Protocol

This skill uses a simplified ESP-NOW payload derived from
`esp-hello-new/examples/gimbal_base`.

On `ESP32C5`, ESP-NOW can also use matching 5 GHz Wi-Fi channels. The current
skill defaults to channel `36`, which is a common 5 GHz option when both peers
support it.

## Packet

The packet is exactly 3 bytes:

```text
[0x01, X_percent, Y_percent]
```

- `0x01` is the fixed packet type marker (`ADC_VALUE`)
- `X_percent` is an integer in `0..100`
- `Y_percent` is an integer in `0..100`

## Mapping

- `X_percent 0..100 -> X angle 180..0`
- `Y_percent 0..100 -> Y angle 70..10`

Both mappings preserve the original reversed-stick behavior used by the source
example's logical angle path.

## Claw Behavior

The claws stay at their closed angle by default.

When the mapped Y angle reaches the top band:

- trigger threshold: `65`
- release threshold: `63`

the script sends a double-clamp pulse to both claw servos:

- left claw open angle: `60`
- right claw open angle: `120`
- closed angle: `90`
