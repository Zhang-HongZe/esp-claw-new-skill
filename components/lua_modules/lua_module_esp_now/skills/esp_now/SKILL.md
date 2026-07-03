---
{
  "name": "esp_now",
  "description": "Use ESP-NOW from Lua to send or receive short peer-to-peer Wi-Fi packets between ESP devices. Requires Wi-Fi to be initialized and started.",
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
      "esp-now",
      "wireless"
    ]
  }
}
---

# ESP-NOW Skill

Use this skill when the user wants ESP-NOW peer-to-peer messaging between ESP
devices from Lua.

## Core Rules

- Import the module with `local esp_now = require("esp_now")`.
- Wi-Fi must already be initialized and started by firmware setup.
- Call `esp_now.init()` before peer management, sending, or event processing.
- Add a peer with `esp_now.add_peer(...)` before sending to it.
- Broadcast uses `ff:ff:ff:ff:ff:ff` and must also be added as a peer first.
- Register one callback with `esp_now.on_event(fn)` and call
  `esp_now.process_events(timeout_ms)` in a loop; callbacks do not run
  automatically.
- Keep event callbacks short. Do not do long blocking work inside the callback.
- Runtime failures return `nil, err`; parameter errors raise Lua errors.

## Minimal Sender/Receiver

```lua
local esp_now = require("esp_now")

local peer = "ff:ff:ff:ff:ff:ff"

assert(esp_now.init())
assert(esp_now.add_peer({
    mac = peer,
    channel = 0,
    ifidx = "sta",
}))

esp_now.on_event(function(ev)
    if ev.type == "recv" then
        print("recv from " .. ev.mac .. ": " .. ev.data)
    elseif ev.type == "send_complete" then
        print("send to " .. ev.mac .. ": " .. ev.status)
    end
end)

assert(esp_now.send({
    mac = peer,
    data = "hello from esp-claw",
}))

while true do
    esp_now.process_events(100)
end
```

## API Quick Reference

- `esp_now.init({ pmk = key16 }) -> true | nil, err`
- `esp_now.deinit() -> true | nil, err`
- `esp_now.add_peer({ mac = "...", channel = 0, ifidx = "sta", encrypt = false, lmk = key16 }) -> true | nil, err`
- `esp_now.del_peer(mac) -> true | nil, err`
- `esp_now.has_peer(mac) -> boolean`
- `esp_now.send({ mac = "...", data = "payload" }) -> true | nil, err`
- `esp_now.on_event(fn_or_nil) -> true`
- `esp_now.process_events(timeout_ms) -> dispatched_count`
- `esp_now.stats() -> table`
- `esp_now.get_mac("sta" | "ap") -> "aa:bb:cc:dd:ee:ff"`

## Events

`recv` events contain `mac` and `data`; `rssi` and `channel` may also be present.

`send_complete` events contain `mac` and `status`, where `status` is `"ok"` or
`"fail"`.
