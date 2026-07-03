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
        print("esp_now recv from " .. ev.mac .. ": " .. ev.data)
        esp_now.send({
            mac = ev.mac,
            data = "echo:" .. ev.data,
        })
    elseif ev.type == "send_complete" then
        print("esp_now send to " .. ev.mac .. ": " .. ev.status)
    end
end)

assert(esp_now.send({
    mac = peer,
    data = "hello from esp-claw",
}))

while true do
    esp_now.process_events(100)
end
