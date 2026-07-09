local arg_schema = require("arg_schema")
local board_manager = require("board_manager")
local camera = require("camera")
local delay = require("delay")
local display = require("display")
local image = require("image")
local motion_detect = require("vision_motion_detect")
local system = require("system")

local DEFAULT_FRAME_INTERVAL_MS = 0
local DEFAULT_CAPTURE_TIMEOUT_MS = 3000
local DEFAULT_DISPLAY_EVERY_N = 1
local DEFAULT_DISPLAY_CROP_SIZE = 240
local DEFAULT_DISPLAY_FLIP_Y = true
local DEFAULT_PERF_LOG_EVERY_N = 30
local DEFAULT_DETECT_STRIDE = 4
local DEFAULT_PIXEL_THRESHOLD = 10 / 255
local DEFAULT_MOVING_THRESHOLD = 0.03

local display_started = false
local camera_started = false

local ARG_SCHEMA = {
    run_seconds = arg_schema.int({ default = 0, min = 0 }),
    frame_interval_ms = arg_schema.int({ default = DEFAULT_FRAME_INTERVAL_MS, min = 0 }),
    capture_timeout_ms = arg_schema.int({ default = DEFAULT_CAPTURE_TIMEOUT_MS, min = 1 }),
    display_every_n = arg_schema.int({ default = DEFAULT_DISPLAY_EVERY_N, min = 1 }),
    display_crop_size = arg_schema.int({ default = DEFAULT_DISPLAY_CROP_SIZE, min = 1 }),
    display_flip_y = arg_schema.bool({ default = DEFAULT_DISPLAY_FLIP_Y }),
    perf_log_every_n = arg_schema.int({ default = DEFAULT_PERF_LOG_EVERY_N, min = 0 }),
    detect_stride = arg_schema.int({ default = DEFAULT_DETECT_STRIDE, min = 1 }),
    pixel_threshold = arg_schema.int({ default = DEFAULT_PIXEL_THRESHOLD, min = 0, max = 1, floor = false }),
    moving_threshold = arg_schema.int({ default = DEFAULT_MOVING_THRESHOLD, min = 0, max = 1, floor = false }),
}

local ctx = arg_schema.parse(args, ARG_SCHEMA)

local function cleanup()
    pcall(motion_detect.reset)
    if display_started then
        pcall(display.end_frame)
        pcall(display.deinit)
        display_started = false
    end
    if camera_started then
        pcall(camera.close)
        camera_started = false
    end
end

local function compute_center_square_source_rect(src_w, src_h)
    local crop = math.min(ctx.display_crop_size, src_w, src_h)
    local src_x = math.floor((src_w - crop) / 2)
    local src_y = math.floor((src_h - crop) / 2)
    return src_x, src_y, crop, crop
end

local function draw_center_cross()
    display.draw_line(display.width // 2 - 8, display.height // 2,
                      display.width // 2 + 8, display.height // 2, "white")
    display.draw_line(display.width // 2, display.height // 2 - 8,
                      display.width // 2, display.height // 2 + 8, "white")
end

local function draw_motion_status(result, dst_x, dst_y, output_w, output_h)
    if result and result.moved then
        display.draw_rect(dst_x, dst_y, output_w, output_h, "yellow")
        display.draw_rect(dst_x + 2, dst_y + 2, math.max(1, output_w - 4), math.max(1, output_h - 4), "yellow")
    else
        display.draw_rect(dst_x, dst_y, output_w, output_h, "green")
    end
    draw_center_cross()
end

local function init_display()
    local panel_handle, io_handle, lcd_width, lcd_height, panel_if =
        board_manager.get_display_lcd_params("display_lcd")
    if not panel_handle then
        error("get_display_lcd_params failed: " .. tostring(io_handle))
    end
    display.init(panel_handle, io_handle, lcd_width, lcd_height, panel_if)
    display_started = true
    pcall(display.backlight, true)
    display.fill_rect(0, 0, display.width, display.height, "black")
end

local function init_camera()
    local camera_paths, path_err = board_manager.get_camera_paths()
    if not camera_paths then
        error("get_camera_paths failed: " .. tostring(path_err))
    end

    print("[gimbal_motion_detect_dl] camera dev_path=" .. tostring(camera_paths.dev_path))
    local opened, open_err = pcall(camera.open, camera_paths.dev_path)
    if not opened then
        error("camera.open failed: " .. tostring(open_err))
    end
    camera_started = true

    local info_ok, info_or_err = pcall(camera.info)
    if not info_ok then
        error("camera.info failed after open: " .. tostring(info_or_err))
    end
    print(string.format("[gimbal_motion_detect_dl] camera stream=%dx%d format=%s",
        info_or_err.width, info_or_err.height, tostring(info_or_err.pixel_format)))

    local flushed, flush_err = pcall(camera.flush)
    if not flushed then
        print("[gimbal_motion_detect_dl] WARN: camera.flush failed: " .. tostring(flush_err))
    end
end

local function run()
    init_camera()
    init_display()
    pcall(motion_detect.reset)

    local stream = camera.info()
    local src_x, src_y, src_w, src_h = compute_center_square_source_rect(stream.width, stream.height)
    local dst_x = math.floor((display.width - src_w) / 2)
    local dst_y = math.floor((display.height - src_h) / 2)
    local frame_index = 0
    local perf_start_ms = system.millis()
    local perf_frames = 0
    local perf_get_ms = 0
    local perf_convert_ms = 0
    local perf_detect_ms = 0
    local perf_display_ms = 0
    local perf_loop_ms = 0
    local start_s = os.time()
    local deadline_s = ctx.run_seconds > 0 and (start_s + ctx.run_seconds) or nil

    print(string.format(
        "[gimbal_motion_detect_dl] start stream=%dx%d format=%s roi=(%d,%d %dx%d) stride=%d pixel=%.3f moving=%.3f",
        stream.width, stream.height, tostring(stream.pixel_format),
        src_x, src_y, src_w, src_h, ctx.detect_stride, ctx.pixel_threshold, ctx.moving_threshold
    ))

    while not deadline_s or os.time() < deadline_s do
        local loop_t0 = system.millis()
        local t0 = loop_t0
        local got_frame, frame_or_err = pcall(camera.get_frame, ctx.capture_timeout_ms)
        local get_ms = system.millis() - t0
        if not got_frame then
            error("camera.get_frame failed: " .. tostring(frame_or_err))
        end
        local frame <close> = frame_or_err

        t0 = system.millis()
        local converted, rgb565_or_err = pcall(image.convert, frame, image.RGB565)
        local convert_ms = system.millis() - t0
        if not converted then
            error("image.convert RGB565 failed: " .. tostring(rgb565_or_err))
        end
        local rgb565 <close> = rgb565_or_err

        t0 = system.millis()
        local detected, motion_result_or_err = pcall(motion_detect.detect, frame, {
            stride = ctx.detect_stride,
            pixel_threshold = ctx.pixel_threshold,
            moving_threshold = ctx.moving_threshold,
        })
        local detect_ms = system.millis() - t0
        if not detected then
            error("vision_motion_detect.detect failed: " .. tostring(motion_result_or_err))
        end
        local motion_result = motion_result_or_err

        frame_index = frame_index + 1

        local display_ms = 0
        if (frame_index % ctx.display_every_n) == 0 then
            t0 = system.millis()
            local output_w, output_h = display.draw_image(dst_x, dst_y, rgb565, {
                mode = "crop",
                source = {
                    x = src_x,
                    y = src_y,
                    width = src_w,
                    height = src_h,
                },
                width = src_w,
                height = src_h,
                flip_y = ctx.display_flip_y,
            })
            draw_motion_status(motion_result, dst_x, dst_y, output_w or src_w, output_h or src_h)
            display_ms = system.millis() - t0
        end

        local loop_ms = system.millis() - loop_t0
        perf_frames = perf_frames + 1
        perf_get_ms = perf_get_ms + get_ms
        perf_convert_ms = perf_convert_ms + convert_ms
        perf_detect_ms = perf_detect_ms + detect_ms
        perf_display_ms = perf_display_ms + display_ms
        perf_loop_ms = perf_loop_ms + loop_ms
        if ctx.perf_log_every_n > 0 and perf_frames >= ctx.perf_log_every_n then
            local elapsed_ms = math.max(1, system.millis() - perf_start_ms)
            local fps = perf_frames * 1000 / elapsed_ms
            print(string.format(
                "[gimbal_motion_detect_dl] perf fps=%.1f avg_ms get=%.1f convert=%.1f detect=%.1f display=%.1f loop=%.1f moved=%s moving=%.3f points=%d/%d",
                fps,
                perf_get_ms / perf_frames,
                perf_convert_ms / perf_frames,
                perf_detect_ms / perf_frames,
                perf_display_ms / perf_frames,
                perf_loop_ms / perf_frames,
                tostring(motion_result.moved),
                motion_result.moving_ratio or 0,
                motion_result.moving_points or 0,
                motion_result.sample_points or 0
            ))
            perf_start_ms = system.millis()
            perf_frames = 0
            perf_get_ms = 0
            perf_convert_ms = 0
            perf_detect_ms = 0
            perf_display_ms = 0
            perf_loop_ms = 0
        end

        if ctx.frame_interval_ms > 0 then
            delay.delay_ms(ctx.frame_interval_ms)
        end
    end
end

local ok, err = xpcall(run, debug.traceback)
cleanup()
if not ok then
    print("[gimbal_motion_detect_dl] ERROR: " .. tostring(err))
    error(err)
end
