local arg_schema = require("arg_schema")
local ble_hid = require("ble_hid")
local delay = require("delay")
local event_publisher = require("event_publisher")
local storage = require("storage")
local thread = require("thread")

local DEFAULT_DEVICE_NAME = "esp-claw-gimbal"
local DEFAULT_BIND_TIMEOUT_MS = 60000
local DEFAULT_POLL_MS = 50
local DEFAULT_KEY_STEP_DEGREES = 3
local DEFAULT_SERVO_MAX_STEP_DEGREES = 2
local DEFAULT_SERVO_UPDATE_MS = 1

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
local DEFAULT_DOUBLE_CLAMP_PULSE_MS = 150
local DEFAULT_Y_TOP_TRIGGER_ANGLE = 60
local DEFAULT_Y_TOP_RELEASE_ANGLE = 55

local REPORT_ID_VENDOR_OUTPUT = 4
local REPORT_SIZE = 5
local REPORT_TYPE_JOYSTICK = 0x01
local REPORT_TYPE_KEYBOARD = 0x02
local HID_AXIS_MIN = -32768
local HID_AXIS_MAX = 32767
local HID_AXIS_RANGE = HID_AXIS_MAX - HID_AXIS_MIN

local HID_KEY_A = 0x04
local HID_KEY_D = 0x07
local HID_KEY_S = 0x16
local HID_KEY_W = 0x1A
local HID_KEY_RIGHT = 0x4F
local HID_KEY_LEFT = 0x50
local HID_KEY_DOWN = 0x51
local HID_KEY_UP = 0x52

local sync = thread.sync
local xy_servo = nil
local y_at_top_latched = false
local ble_initialized = false

local function raw_arg(name, default)
    if type(args) == "table" and args[name] ~= nil then
        return args[name]
    end
    return default
end

local ARG_SCHEMA = {
    bind_timeout_ms = arg_schema.int({ default = DEFAULT_BIND_TIMEOUT_MS, min = 1000 }),
    poll_ms = arg_schema.int({ default = DEFAULT_POLL_MS, min = 1 }),
    key_step_degrees = arg_schema.int({ default = DEFAULT_KEY_STEP_DEGREES, min = 1, max = 30 }),
    servo_max_step_degrees = arg_schema.int({ default = DEFAULT_SERVO_MAX_STEP_DEGREES, min = 1, max = 30 }),
    servo_update_ms = arg_schema.int({ default = DEFAULT_SERVO_UPDATE_MS, min = 1 }),
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
ctx.device_name = raw_arg("device_name", DEFAULT_DEVICE_NAME)
ctx.xy_servo_worker_path = raw_arg(
    "xy_servo_worker_path",
    storage.join_path(storage.get_root_dir(), "skills", "gimbal_base", "scripts", "xy_servo_worker.lua")
)

local function clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    end
    if value > max_value then
        return max_value
    end
    return value
end

local function check_result(label, ok, err)
    if not ok then
        error(label .. " failed: " .. tostring(err))
    end
end

local function delete_queue_best_effort(queue_name)
    for _ = 1, 32 do
        local msg = sync.queue_recv(queue_name, 0)
        if not msg then
            break
        end
    end
    pcall(sync.queue_delete, queue_name)
end

local function validate_config()
    if type(ctx.device_name) ~= "string" or ctx.device_name == "" or #ctx.device_name > 29 then
        error("device_name must contain 1..29 bytes")
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

local function publish_im(text)
    local ok, err = pcall(event_publisher.publish_message, text)
    if not ok then
        print("[gimbal_base] IM notification failed: " .. tostring(err))
    end
end

local function map_axis_to_angle(value, min_angle, max_angle)
    local normalized = (clamp(value, HID_AXIS_MIN, HID_AXIS_MAX) - HID_AXIS_MIN) / HID_AXIS_RANGE
    return max_angle - (max_angle - min_angle) * normalized
end

local function send_xy_target(x_angle, y_angle, timeout_ms)
    local x_target = clamp(x_angle, ctx.x_min_angle, ctx.x_max_angle)
    local y_target = clamp(y_angle, ctx.y_min_angle, ctx.y_max_angle)

    xy_servo.x_target = x_target
    xy_servo.y_target = y_target

    local ok, err = sync.queue_send(
        xy_servo.queue_name,
        string.format("xy,%.3f,%.3f", x_target, y_target),
        timeout_ms or 0
    )
    if not ok and err ~= "timeout" then
        print("[gimbal_base] xy target send failed: " .. tostring(err))
    end
    return ok, err
end

local function send_claw_command(command, timeout_ms)
    local ok, err = sync.queue_send(
        xy_servo.queue_name,
        "claw," .. command,
        timeout_ms or 0
    )
    if not ok and err ~= "timeout" then
        print("[gimbal_base] claw command send failed: " .. tostring(err))
    end
    return ok, err
end

local function update_claw_for_y(y_angle)
    if y_angle > ctx.y_top_trigger_angle then
        if not y_at_top_latched then
            print("[gimbal_base] y reached clamp threshold, triggering double clamp")
            send_claw_command("double", 0)
            y_at_top_latched = true
        end
    elseif y_angle < ctx.y_top_release_angle then
        y_at_top_latched = false
        send_claw_command("close", 0)
    end
end

local function start_xy_servo_worker()
    local queue_name = "gimbal_base_xy_target"
    local job_name = "gimbal_base_xy_servo"

    pcall(thread.stop, job_name, 1000)
    delete_queue_best_effort(queue_name)
    check_result("thread.sync.queue_create " .. queue_name,
                 sync.queue_create(queue_name, { depth = 16, item_size = 64 }))

    xy_servo = {
        queue_name = queue_name,
        job_name = job_name,
        x_target = clamp(ctx.x_init_angle, ctx.x_min_angle, ctx.x_max_angle),
        y_target = clamp(ctx.y_init_angle, ctx.y_min_angle, ctx.y_max_angle),
    }

    local ok, err = thread.start(ctx.xy_servo_worker_path, {
        queue_name = queue_name,
        x_gpio = ctx.x_gpio,
        y_gpio = ctx.y_gpio,
        left_claw_gpio = ctx.left_claw_gpio,
        right_claw_gpio = ctx.right_claw_gpio,
        frequency_hz = ctx.frequency_hz,
        min_pulse_us = ctx.min_pulse_us,
        max_pulse_us = ctx.max_pulse_us,
        x_start_angle = ctx.x_init_angle,
        y_start_angle = ctx.y_init_angle,
        x_min_angle = ctx.x_min_angle,
        x_max_angle = ctx.x_max_angle,
        y_min_angle = ctx.y_min_angle,
        y_max_angle = ctx.y_max_angle,
        max_step_degrees = ctx.servo_max_step_degrees,
        update_ms = ctx.servo_update_ms,
        claw_closed_angle = ctx.claw_closed_angle,
        left_claw_open_angle = ctx.left_claw_open_angle,
        right_claw_open_angle = ctx.right_claw_open_angle,
        double_clamp_pulse_ms = ctx.double_clamp_pulse_ms,
    }, {
        name = job_name,
        exclusive = job_name,
        replace = true,
        timeout_ms = 0,
    })
    check_result("thread.start " .. job_name, ok, err)

    check_result("queue initial xy target", send_xy_target(xy_servo.x_target, xy_servo.y_target, 100))
end

local function cleanup()
    if ble_initialized then
        pcall(ble_hid.release_all)
        pcall(ble_hid.stop)
        pcall(ble_hid.deinit)
        ble_initialized = false
    end
    if xy_servo then
        pcall(thread.stop, xy_servo.job_name, 1000)
        delete_queue_best_effort(xy_servo.queue_name)
        xy_servo = nil
    end
end

local function parse_i16_le(lo, hi)
    local value = lo + hi * 256
    if value >= 0x8000 then
        value = value - 0x10000
    end
    return value
end

local function apply_joystick_report(data)
    local _, x_lo, x_hi, y_lo, y_hi = string.byte(data, 1, REPORT_SIZE)
    local x_value = parse_i16_le(x_lo, x_hi)
    local y_value = parse_i16_le(y_lo, y_hi)
    local x_target = map_axis_to_angle(x_value, ctx.x_min_angle, ctx.x_max_angle)
    local y_target = map_axis_to_angle(y_value, ctx.y_min_angle, ctx.y_max_angle)

    send_xy_target(x_target, y_target, 0)
    update_claw_for_y(y_target)
end

local function apply_keyboard_report(data)
    local _, _, keycode, pressed = string.byte(data, 1, 4)
    if pressed ~= 1 then
        return
    end

    if keycode == HID_KEY_LEFT or keycode == HID_KEY_A then
        send_xy_target(xy_servo.x_target - ctx.key_step_degrees, xy_servo.y_target, 0)
    elseif keycode == HID_KEY_RIGHT or keycode == HID_KEY_D then
        send_xy_target(xy_servo.x_target + ctx.key_step_degrees, xy_servo.y_target, 0)
    elseif keycode == HID_KEY_UP or keycode == HID_KEY_W then
        send_xy_target(xy_servo.x_target, xy_servo.y_target + ctx.key_step_degrees, 0)
        update_claw_for_y(xy_servo.y_target)
    elseif keycode == HID_KEY_DOWN or keycode == HID_KEY_S then
        send_xy_target(xy_servo.x_target, xy_servo.y_target - ctx.key_step_degrees, 0)
        update_claw_for_y(xy_servo.y_target)
    end
end

local function handle_output_report(event)
    if type(event) ~= "table" or event.report_id ~= REPORT_ID_VENDOR_OUTPUT or
            type(event.data) ~= "string" or #event.data ~= REPORT_SIZE then
        return
    end

    local report_type = string.byte(event.data, 1)
    if report_type == REPORT_TYPE_JOYSTICK then
        apply_joystick_report(event.data)
    elseif report_type == REPORT_TYPE_KEYBOARD then
        apply_keyboard_report(event.data)
    end
end

local function wait_for_bond()
    local waited_ms = 0
    while waited_ms < ctx.bind_timeout_ms do
        local status = ble_hid.status()
        if status.connected and status.bonded then
            return true
        end
        delay.delay_ms(ctx.poll_ms)
        waited_ms = waited_ms + ctx.poll_ms
    end
    return false
end

local function run()
    validate_config()
    start_xy_servo_worker()

    local ok, err = ble_hid.init({ name = ctx.device_name })
    check_result("ble_hid.init", ok, err)
    ble_initialized = true
    ok, err = ble_hid.start({ name = ctx.device_name })
    check_result("ble_hid.start", ok, err)

    print(string.format(
        "[gimbal_base] advertising name=%s bind_timeout_ms=%d x_gpio=%d y_gpio=%d",
        ctx.device_name, ctx.bind_timeout_ms, ctx.x_gpio, ctx.y_gpio
    ))

    if not wait_for_bond() then
        publish_im(string.format("云台底座蓝牙绑定超时（设备名：%s）。", ctx.device_name))
        print("[gimbal_base] bind timeout")
        return
    end

    publish_im(string.format("云台底座蓝牙绑定成功（设备名：%s）。", ctx.device_name))
    print("[gimbal_base] bonded; receiving HID output reports")

    while true do
        local event, receive_err = ble_hid.receive(ctx.poll_ms)
        if event then
            handle_output_report(event)
        elseif receive_err ~= "timeout" then
            error("ble_hid.receive failed: " .. tostring(receive_err))
        end
    end
end

local ok, err = xpcall(run, debug.traceback)
cleanup()
if not ok then
    print("[gimbal_base] ERROR: " .. tostring(err))
    error(err)
end
