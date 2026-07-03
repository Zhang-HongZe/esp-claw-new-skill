local arg_schema = require("arg_schema")
local delay = require("delay")
local esp_now = require("esp_now")
local ledc = require("ledc")

local DEFAULT_PMK = "pmk1234567890123"
local DEFAULT_PEER_MAC = "ff:ff:ff:ff:ff:ff"
local DEFAULT_CHANNEL = 36
local DEFAULT_IFIDX = "sta"
local DEFAULT_POLL_MS = 50

local DEFAULT_X_GPIO = 4
local DEFAULT_Y_GPIO = 5
local DEFAULT_LEFT_CLAW_GPIO = 12
local DEFAULT_RIGHT_CLAW_GPIO = 28

local DEFAULT_FREQUENCY_HZ = 50
local DEFAULT_MIN_PULSE_US = 500
local DEFAULT_MAX_PULSE_US = 2500

local DEFAULT_X_INIT_ANGLE = 90
local DEFAULT_Y_INIT_ANGLE = 50
local DEFAULT_X_MIN_ANGLE = 0
local DEFAULT_X_MAX_ANGLE = 180
local DEFAULT_Y_MIN_ANGLE = 10
local DEFAULT_Y_MAX_ANGLE = 70

local DEFAULT_CLAW_CLOSED_ANGLE = 90
local DEFAULT_LEFT_CLAW_OPEN_ANGLE = 60
local DEFAULT_RIGHT_CLAW_OPEN_ANGLE = 120
local DEFAULT_DOUBLE_CLAMP_PULSE_MS = 140
local DEFAULT_Y_TOP_TRIGGER_ANGLE = 65
local DEFAULT_Y_TOP_RELEASE_ANGLE = 63

local ADC_VALUE_TAG = 0x01
local PERCENT_MIN = 0
local PERCENT_MAX = 100

local function raw_arg(name, default)
    if type(args) == "table" and args[name] ~= nil then
        return args[name]
    end
    return default
end

local ARG_SCHEMA = {
    channel = arg_schema.int({ default = DEFAULT_CHANNEL, min = 0 }),
    poll_ms = arg_schema.int({ default = DEFAULT_POLL_MS, min = 0 }),
    x_gpio = arg_schema.int({ default = DEFAULT_X_GPIO, min = 0 }),
    y_gpio = arg_schema.int({ default = DEFAULT_Y_GPIO, min = 0 }),
    left_claw_gpio = arg_schema.int({ default = DEFAULT_LEFT_CLAW_GPIO, min = 0 }),
    right_claw_gpio = arg_schema.int({ default = DEFAULT_RIGHT_CLAW_GPIO, min = 0 }),
    frequency_hz = arg_schema.int({ default = DEFAULT_FREQUENCY_HZ, min = 1 }),
    min_pulse_us = arg_schema.int({ default = DEFAULT_MIN_PULSE_US, min = 1 }),
    max_pulse_us = arg_schema.int({ default = DEFAULT_MAX_PULSE_US, min = 1 }),
    x_init_angle = arg_schema.int({ default = DEFAULT_X_INIT_ANGLE, min = 0, max = 180 }),
    y_init_angle = arg_schema.int({ default = DEFAULT_Y_INIT_ANGLE, min = 0, max = 180 }),
    x_min_angle = arg_schema.int({ default = DEFAULT_X_MIN_ANGLE, min = 0, max = 180 }),
    x_max_angle = arg_schema.int({ default = DEFAULT_X_MAX_ANGLE, min = 0, max = 180 }),
    y_min_angle = arg_schema.int({ default = DEFAULT_Y_MIN_ANGLE, min = 0, max = 180 }),
    y_max_angle = arg_schema.int({ default = DEFAULT_Y_MAX_ANGLE, min = 0, max = 180 }),
    claw_closed_angle = arg_schema.int({ default = DEFAULT_CLAW_CLOSED_ANGLE, min = 0, max = 180 }),
    left_claw_open_angle = arg_schema.int({ default = DEFAULT_LEFT_CLAW_OPEN_ANGLE, min = 0, max = 180 }),
    right_claw_open_angle = arg_schema.int({ default = DEFAULT_RIGHT_CLAW_OPEN_ANGLE, min = 0, max = 180 }),
    double_clamp_pulse_ms = arg_schema.int({ default = DEFAULT_DOUBLE_CLAMP_PULSE_MS, min = 0 }),
    y_top_trigger_angle = arg_schema.int({ default = DEFAULT_Y_TOP_TRIGGER_ANGLE, min = 0, max = 180 }),
    y_top_release_angle = arg_schema.int({ default = DEFAULT_Y_TOP_RELEASE_ANGLE, min = 0, max = 180 })
}

local ctx = arg_schema.parse(args, ARG_SCHEMA)
ctx.pmk = raw_arg("pmk", DEFAULT_PMK)
ctx.peer_mac = raw_arg("peer_mac", DEFAULT_PEER_MAC)
ctx.ifidx = raw_arg("ifidx", DEFAULT_IFIDX)

local servos = {}
local latest_input = nil
local latest_seq = 0
local applied_seq = 0
local y_at_top_latched = false
local esp_now_initialized = false

local function clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    end
    if value > max_value then
        return max_value
    end
    return value
end

local function validate_string(name, value)
    if type(value) ~= "string" or value == "" then
        error(name .. " must be a non-empty string")
    end
end

local function validate_mac(name, value)
    validate_string(name, value)
    if not value:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then
        error(name .. " must be a MAC string like aa:bb:cc:dd:ee:ff")
    end
end

local function validate_config()
    validate_string("pmk", ctx.pmk)
    if #ctx.pmk ~= 16 then
        error("pmk must be exactly 16 bytes")
    end

    validate_mac("peer_mac", ctx.peer_mac)
    validate_string("ifidx", ctx.ifidx)
    if ctx.ifidx ~= "sta" and ctx.ifidx ~= "ap" then
        error("ifidx must be 'sta' or 'ap'")
    end

    if ctx.max_pulse_us <= ctx.min_pulse_us then
        error("max_pulse_us must be greater than min_pulse_us")
    end
    if ctx.x_min_angle > ctx.x_max_angle then
        error("x_min_angle must be <= x_max_angle")
    end
    if ctx.y_min_angle > ctx.y_max_angle then
        error("y_min_angle must be <= y_max_angle")
    end
    if ctx.y_top_release_angle > ctx.y_top_trigger_angle then
        error("y_top_release_angle must be <= y_top_trigger_angle")
    end
end

local function angle_to_duty_percent(angle)
    local clamped = clamp(angle, 0, 180)
    local pulse_width_us = ctx.min_pulse_us +
        (ctx.max_pulse_us - ctx.min_pulse_us) * clamped / 180
    return pulse_width_us * ctx.frequency_hz / 10000
end

local function map_percent_to_angle(percent, min_angle, max_angle)
    local clamped_percent = clamp(percent, PERCENT_MIN, PERCENT_MAX)
    return max_angle - (max_angle - min_angle) * clamped_percent / PERCENT_MAX
end

local function new_servo(name, gpio, start_angle)
    local pwm = ledc.new({
        gpio = gpio,
        frequency_hz = ctx.frequency_hz,
        duty_percent = angle_to_duty_percent(start_angle)
    })
    pwm:start()
    return {
        name = name,
        gpio = gpio,
        pwm = pwm,
        angle = start_angle
    }
end

local function set_servo_angle(servo, angle)
    local clamped_angle = clamp(angle, 0, 180)
    servo.pwm:set_duty(angle_to_duty_percent(clamped_angle))
    servo.angle = clamped_angle
end

local function close_claws()
    set_servo_angle(servos.left_claw, ctx.claw_closed_angle)
    set_servo_angle(servos.right_claw, ctx.claw_closed_angle)
end

local function open_claws()
    set_servo_angle(servos.left_claw, ctx.left_claw_open_angle)
    set_servo_angle(servos.right_claw, ctx.right_claw_open_angle)
end

local function double_clamp()
    for _ = 1, 2 do
        open_claws()
        delay.delay_ms(ctx.double_clamp_pulse_ms)
        close_claws()
        delay.delay_ms(ctx.double_clamp_pulse_ms)
    end
end

local function cleanup_servos()
    for _, servo in pairs(servos) do
        if servo and servo.pwm then
            pcall(servo.pwm.stop, servo.pwm)
            pcall(servo.pwm.close, servo.pwm)
        end
    end
    servos = {}
end

local function cleanup_esp_now()
    if esp_now_initialized then
        pcall(esp_now.on_event, nil)
        pcall(esp_now.deinit)
        esp_now_initialized = false
    end
end

local function cleanup()
    cleanup_esp_now()
    cleanup_servos()
end

local function init_servos()
    servos.x = new_servo("x", ctx.x_gpio, ctx.x_init_angle)
    servos.y = new_servo("y", ctx.y_gpio, ctx.y_init_angle)
    servos.left_claw = new_servo("left_claw", ctx.left_claw_gpio, ctx.claw_closed_angle)
    servos.right_claw = new_servo("right_claw", ctx.right_claw_gpio, ctx.claw_closed_angle)
    close_claws()
end

local function apply_latest_input()
    if latest_seq == 0 or applied_seq == latest_seq or not latest_input then
        return
    end

    applied_seq = latest_seq

    local x_angle = map_percent_to_angle(latest_input.x_percent, ctx.x_min_angle, ctx.x_max_angle)
    local y_angle = map_percent_to_angle(latest_input.y_percent, ctx.y_min_angle, ctx.y_max_angle)

    set_servo_angle(servos.x, x_angle)
    set_servo_angle(servos.y, y_angle)

    if y_angle >= ctx.y_top_trigger_angle then
        if not y_at_top_latched then
            print("[gimbal_base] y reached clamp threshold, triggering double clamp")
            double_clamp()
            y_at_top_latched = true
        end
    elseif y_angle < ctx.y_top_release_angle then
        y_at_top_latched = false
        close_claws()
    end

    -- print(string.format(
    --     "[gimbal_base] recv from %s x=%d%% y=%d%% -> x_angle=%.1f y_angle=%.1f",
    --     tostring(latest_input.mac),
    --     latest_input.x_percent,
    --     latest_input.y_percent,
    --     x_angle,
    --     y_angle
    -- ))
end

local function handle_recv_event(ev)
    if type(ev.data) ~= "string" or #ev.data ~= 3 then
        return
    end

    local tag, x_percent, y_percent = string.byte(ev.data, 1, 3)
    if tag ~= ADC_VALUE_TAG then
        return
    end
    if not x_percent or not y_percent then
        return
    end
    if x_percent < PERCENT_MIN or x_percent > PERCENT_MAX or
            y_percent < PERCENT_MIN or y_percent > PERCENT_MAX then
        return
    end

    latest_input = {
        mac = ev.mac,
        x_percent = x_percent,
        y_percent = y_percent
    }
    latest_seq = latest_seq + 1
end

local function init_esp_now()
    assert(esp_now.init({ pmk = ctx.pmk }))
    esp_now_initialized = true

    assert(esp_now.add_peer({
        mac = ctx.peer_mac,
        channel = ctx.channel,
        ifidx = ctx.ifidx
    }))

    esp_now.on_event(function(ev)
        if ev.type == "recv" then
            handle_recv_event(ev)
        elseif ev.type == "send_complete" and ev.status ~= "ok" then
            print("[gimbal_base] send_complete status=" .. tostring(ev.status) .. " mac=" .. tostring(ev.mac))
        end
    end)
end

local function run()
    validate_config()

    print(string.format(
        "[gimbal_base] starting peer=%s channel=%d x_gpio=%d y_gpio=%d left_claw_gpio=%d right_claw_gpio=%d",
        ctx.peer_mac,
        ctx.channel,
        ctx.x_gpio,
        ctx.y_gpio,
        ctx.left_claw_gpio,
        ctx.right_claw_gpio
    ))

    init_servos()
    init_esp_now()

    while true do
        esp_now.process_events(ctx.poll_ms)
        apply_latest_input()
    end
end

local ok, err = xpcall(run, debug.traceback)
cleanup()
if not ok then
    print("[gimbal_base] ERROR: " .. tostring(err))
    error(err)
end
