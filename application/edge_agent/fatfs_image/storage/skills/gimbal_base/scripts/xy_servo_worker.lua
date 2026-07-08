local delay = require("delay")
local ledc = require("ledc")
local thread = require("thread")

local sync = thread.sync

local queue_name = assert(args.queue_name, "queue_name is required")
local x_gpio = assert(args.x_gpio, "x_gpio is required")
local y_gpio = assert(args.y_gpio, "y_gpio is required")
local left_claw_gpio = assert(args.left_claw_gpio, "left_claw_gpio is required")
local right_claw_gpio = assert(args.right_claw_gpio, "right_claw_gpio is required")
local frequency_hz = args.frequency_hz or 50
local min_pulse_us = args.min_pulse_us or 500
local max_pulse_us = args.max_pulse_us or 2500
local x_min_angle = args.x_min_angle or 0
local x_max_angle = args.x_max_angle or 180
local y_min_angle = args.y_min_angle or 0
local y_max_angle = args.y_max_angle or 180
local update_ms = args.update_ms or 1
local max_step_degrees = args.max_step_degrees or 2
local claw_closed_angle = args.claw_closed_angle or 90
local left_claw_open_angle = args.left_claw_open_angle or 60
local right_claw_open_angle = args.right_claw_open_angle or 120
local double_clamp_pulse_ms = args.double_clamp_pulse_ms or 150
local x_current = args.x_start_angle or 90
local y_current = args.y_start_angle or 90
local x_target = x_current
local y_target = y_current
local min_delta_degrees = 0.05
local x_pwm
local y_pwm
local left_claw_pwm
local right_claw_pwm
local claw_sequence = nil
local claw_step_index = 0
local claw_remaining_ms = 0

local function clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    end
    if value > max_value then
        return max_value
    end
    return value
end

local function approach(current, target, max_step)
    if target > current + max_step then
        return current + max_step
    end
    if target < current - max_step then
        return current - max_step
    end
    return target
end

local function angle_to_duty_percent(angle)
    local pulse_width_us = min_pulse_us +
        (max_pulse_us - min_pulse_us) * clamp(angle, 0, 180) / 180
    return pulse_width_us * frequency_hz / 10000
end

local function set_pwm_angle(pwm, angle)
    pwm:set_duty(angle_to_duty_percent(angle))
end

local function apply_claw_action(action)
    if action == "open" then
        set_pwm_angle(left_claw_pwm, left_claw_open_angle)
        set_pwm_angle(right_claw_pwm, right_claw_open_angle)
    elseif action == "close" then
        set_pwm_angle(left_claw_pwm, claw_closed_angle)
        set_pwm_angle(right_claw_pwm, claw_closed_angle)
    end
end

local function start_claw_sequence(sequence)
    claw_sequence = sequence
    claw_step_index = 1
    claw_remaining_ms = 0
end

local function handle_claw_command(command)
    if command == "open" then
        claw_sequence = nil
        claw_step_index = 0
        apply_claw_action("open")
    elseif command == "close" then
        claw_sequence = nil
        claw_step_index = 0
        apply_claw_action("close")
    elseif command == "pulse" then
        start_claw_sequence({
            { action = "open", delay_ms = double_clamp_pulse_ms },
            { action = "close", delay_ms = double_clamp_pulse_ms },
        })
    elseif command == "double" then
        start_claw_sequence({
            { action = "open", delay_ms = double_clamp_pulse_ms },
            { action = "close", delay_ms = double_clamp_pulse_ms },
            { action = "open", delay_ms = double_clamp_pulse_ms },
            { action = "close", delay_ms = double_clamp_pulse_ms },
        })
    end
end

local function parse_target(msg)
    if type(msg) ~= "string" then
        return
    end
    local command, a, b = msg:match("^([^,]+),([^,]+),?([^,]*)$")
    if command == "xy" then
        local next_x = tonumber(a)
        local next_y = tonumber(b)
        if next_x and next_y then
            x_target = clamp(next_x, x_min_angle, x_max_angle)
            y_target = clamp(next_y, y_min_angle, y_max_angle)
        end
    elseif command == "claw" then
        handle_claw_command(a)
    else
        local x_text, y_text = msg:match("^([^,]+),([^,]+)$")
        local next_x = tonumber(x_text)
        local next_y = tonumber(y_text)
        if next_x and next_y then
            x_target = clamp(next_x, x_min_angle, x_max_angle)
            y_target = clamp(next_y, y_min_angle, y_max_angle)
        end
    end
end

local function read_latest_target()
    local msg, err = sync.queue_recv(queue_name, 0)
    if err == "stopped" then
        return false
    end
    while msg do
        parse_target(msg)
        msg, err = sync.queue_recv(queue_name, 0)
        if err == "stopped" then
            return false
        end
    end
    return true
end

local function apply_axis(pwm, current, next_angle)
    if math.abs(next_angle - current) >= min_delta_degrees then
        set_pwm_angle(pwm, next_angle)
        return next_angle
    end
    return current
end

local function update_claw_sequence()
    if not claw_sequence or claw_step_index == 0 then
        return
    end

    if claw_remaining_ms > 0 then
        claw_remaining_ms = claw_remaining_ms - update_ms
        return
    end

    local step = claw_sequence[claw_step_index]
    if not step then
        claw_sequence = nil
        claw_step_index = 0
        claw_remaining_ms = 0
        return
    end

    apply_claw_action(step.action)
    claw_remaining_ms = step.delay_ms or 0
    claw_step_index = claw_step_index + 1
end

local function cleanup()
    if x_pwm then
        pcall(x_pwm.stop, x_pwm)
        pcall(x_pwm.close, x_pwm)
        x_pwm = nil
    end
    if y_pwm then
        pcall(y_pwm.stop, y_pwm)
        pcall(y_pwm.close, y_pwm)
        y_pwm = nil
    end
    if left_claw_pwm then
        pcall(left_claw_pwm.stop, left_claw_pwm)
        pcall(left_claw_pwm.close, left_claw_pwm)
        left_claw_pwm = nil
    end
    if right_claw_pwm then
        pcall(right_claw_pwm.stop, right_claw_pwm)
        pcall(right_claw_pwm.close, right_claw_pwm)
        right_claw_pwm = nil
    end
end

local function run()
    x_current = clamp(x_current, x_min_angle, x_max_angle)
    y_current = clamp(y_current, y_min_angle, y_max_angle)
    x_target = x_current
    y_target = y_current

    x_pwm = ledc.new({
        gpio = x_gpio,
        frequency_hz = frequency_hz,
        duty_percent = angle_to_duty_percent(x_current),
    })
    y_pwm = ledc.new({
        gpio = y_gpio,
        frequency_hz = frequency_hz,
        duty_percent = angle_to_duty_percent(y_current),
    })
    left_claw_pwm = ledc.new({
        gpio = left_claw_gpio,
        frequency_hz = frequency_hz,
        duty_percent = angle_to_duty_percent(claw_closed_angle),
    })
    right_claw_pwm = ledc.new({
        gpio = right_claw_gpio,
        frequency_hz = frequency_hz,
        duty_percent = angle_to_duty_percent(claw_closed_angle),
    })
    x_pwm:start()
    y_pwm:start()
    left_claw_pwm:start()
    right_claw_pwm:start()
    print(string.format(
        "[gimbal_base] xy servo worker started x_gpio=%d y_gpio=%d claw_gpios=%d,%d update_ms=%d max_step=%s",
        x_gpio, y_gpio, left_claw_gpio, right_claw_gpio, update_ms, tostring(max_step_degrees)
    ))

    while true do
        if not read_latest_target() then
            break
        end

        local next_x = approach(x_current, x_target, max_step_degrees)
        local next_y = approach(y_current, y_target, max_step_degrees)
        x_current = apply_axis(x_pwm, x_current, next_x)
        y_current = apply_axis(y_pwm, y_current, next_y)
        update_claw_sequence()

        delay.delay_ms(update_ms)
    end
end

local ok, err = xpcall(run, debug.traceback)
cleanup()
if not ok then
    print("[gimbal_base] xy servo worker ERROR: " .. tostring(err))
    error(err)
end
