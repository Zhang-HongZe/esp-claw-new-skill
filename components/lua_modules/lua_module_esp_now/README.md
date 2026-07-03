# Lua ESP-NOW

This module exposes ESP-IDF ESP-NOW send/receive primitives to Lua scripts.

## How to call

- Import it with `local esp_now = require("esp_now")`
- Ensure Wi-Fi has already been initialized and started by the firmware.
- Call `esp_now.init()` before adding peers, sending data, or processing events.
- Register one callback with `esp_now.on_event(fn)`.
- Call `esp_now.process_events(timeout_ms)` in a loop to dispatch receive and
  send-completion events on the Lua task.
- Call `esp_now.deinit()` when the script owns the ESP-NOW session and is done.

This module does not start or stop Wi-Fi and does not change Wi-Fi mode or
channel. Keep Wi-Fi lifecycle and channel selection in the app or board setup.

Most runtime failures return `nil, err`. Parameter type and shape errors raise a
Lua error.

## API

### `esp_now.init(opts)`

Initializes ESP-NOW and registers internal send/receive callbacks.

`opts` is optional:

- `pmk`: optional 16-byte primary master key string.

Returns `true` on success, or `nil, err` on failure. If Wi-Fi is not initialized
or started, ESP-IDF returns a Wi-Fi or ESP-NOW error.

### `esp_now.deinit()`

Unregisters callbacks, deinitializes ESP-NOW, and clears queued events.
Idempotent. Returns `true` on success or `nil, err`.

### `esp_now.add_peer(opts)`

Adds or updates one peer.

Fields:

- `mac`: required peer MAC, either `"aa:bb:cc:dd:ee:ff"` or a 6-byte string.
- `channel`: optional Wi-Fi channel `0..14`, defaults to `0`.
- `ifidx`: optional `"sta"` or `"ap"`, defaults to `"sta"`.
- `encrypt`: optional boolean, defaults to `false`.
- `lmk`: required 16-byte local master key when `encrypt = true`.

Returns `true` on success or `nil, err`.

### `esp_now.del_peer(mac)`

Deletes one peer by MAC. Returns `true` on success or `nil, err`.

### `esp_now.has_peer(mac)`

Returns `true` if the peer exists, otherwise `false`.

### `esp_now.send(opts)`

Sends one payload to a peer.

Fields:

- `mac`: required destination MAC.
- `data`: required string payload, up to the ESP-IDF ESP-NOW v1 payload limit.

Returns `true` after the packet is accepted for sending, or `nil, err`. Delivery
result arrives later as a `send_complete` event.

Broadcast uses MAC `ff:ff:ff:ff:ff:ff`; add that peer before sending.

### `esp_now.on_event(fn_or_nil)`

Registers or clears the single event callback. Replacing the callback clears
queued events. Events are delivered only when Lua calls `process_events`.

Event types:

```lua
{ type = "recv", mac = "aa:bb:cc:dd:ee:ff", data = "payload", rssi = -40, channel = 6 }
{ type = "send_complete", mac = "aa:bb:cc:dd:ee:ff", status = "ok" } -- or "fail"
```

`rssi` and `channel` are present only when the ESP-IDF receive callback provides
RX metadata.

### `esp_now.process_events(timeout_ms)`

Dispatches up to 8 queued events to the registered callback. `timeout_ms`
defaults to `0` and only applies while waiting for the first event. Returns the
number of dispatched events.

### `esp_now.stats()`

Returns a table with module diagnostics:

- `initialized`
- `event_dropped`
- `event_queue_capacity`
- `event_queue_depth`
- `max_data_len`
- `version`, `peer_total`, and `peer_encrypted` when initialized and available.

### `esp_now.get_mac(kind)`

Returns the device Wi-Fi MAC string. `kind` is optional and can be `"sta"`
(default) or `"ap"`.

## Example

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

## Limits and ownership

- ESP-NOW shares the Wi-Fi radio. Wi-Fi mode, channel, and power-save policy can
  affect peer reachability and latency.
- The event queue holds 32 events. If it fills, new events are dropped and
  `stats().event_dropped` increments.
- Do not block for a long time inside the event callback. Keep callback work
  short and return to the `process_events` loop.
