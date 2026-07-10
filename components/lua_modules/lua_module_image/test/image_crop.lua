--[[
  image_crop.lua

  Live LCD test for image.crop(). Each captured camera frame is center-cropped
  into a square preview, optionally flipped vertically, and drawn without using
  display-side crop mode. The script checks RGB565 and GRAY8 metadata and
  verifies cropped frames outlive an explicit source release.
--]]

local board_manager = require("board_manager")
local camera = require("camera")
local delay = require("delay")
local display = require("display")
local image = require("image")
local system = require("system")

local TAG = "[image_crop]"
local RUN_SECONDS = 20
local CAPTURE_TIMEOUT_MS = 3000
local FRAME_INTERVAL_MS = 40
local CAMERA_OPEN_OPTS = { format = { "JPEG", "RGBP", "YUYV", "UYVY", "YU12" } }
local RELEASE_CHECK_EVERY_N = 10

local display_started = false
local camera_started = false

local function cleanup()
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

local function assert_true(value, message)
    if not value then
        error(message, 2)
    end
end

local function assert_info(view, expected_w, expected_h, expected_format, expected_bytes, label)
    local info = view:info()
    assert_true(info.valid == true, label .. ": view should be valid")
    assert_true(info.width == expected_w and info.height == expected_h,
        string.format("%s: size %dx%d expected %dx%d", label, info.width, info.height, expected_w, expected_h))
    assert_true(info.pixel_format == expected_format,
        string.format("%s: format=%s expected=%s", label, tostring(info.pixel_format), expected_format))
    assert_true(info.bytes == expected_bytes,
        string.format("%s: bytes=%d expected=%d", label, info.bytes, expected_bytes))
end

local function center_square_rect(width, height)
    local side = math.min(width, height)
    return (width - side) // 2, (height - side) // 2, side, side
end

local panel_handle, io_handle, lcd_width, lcd_height, panel_if =
    board_manager.get_display_lcd_params("display_lcd")
if not panel_handle then
    print(TAG .. " SKIP: get_display_lcd_params failed: " .. tostring(io_handle))
    return
end

local camera_paths, path_err = board_manager.get_camera_paths()
if not camera_paths then
    print(TAG .. " SKIP: get_camera_paths failed: " .. tostring(path_err))
    return
end

local ok, err = pcall(display.init, panel_handle, io_handle, lcd_width, lcd_height, panel_if)
if not ok then
    print(TAG .. " SKIP: display.init failed: " .. tostring(err))
    return
end
display_started = true

ok, err = pcall(camera.open, camera_paths.dev_path, CAMERA_OPEN_OPTS)
if not ok then
    print(TAG .. " SKIP: camera.open failed: " .. tostring(err))
    cleanup()
    return
end
camera_started = true

local run_ok, run_err = xpcall(function()
    local overlay_h = 56
    local start_ms = system.millis()
    local deadline_ms = start_ms + RUN_SECONDS * 1000
    local frames = 0
    local crop_sum = 0
    local gray_sum = 0
    local release_checks = 0

    print(string.format("%s start %ds display=%dx%d", TAG, RUN_SECONDS, display.width, display.height))

    while system.millis() < deadline_ms do
        local now_ms = system.millis()
        local remaining_s = math.max(0, math.floor((deadline_ms - now_ms) / 1000))

        local frame <close> = camera.get_frame(CAPTURE_TIMEOUT_MS)
        assert_true(frame ~= nil, "camera.get_frame returned nil")
        local info = frame:info()
        local x, y, w, h = center_square_rect(info.width, info.height)

        local t0 = system.millis()
        local crop = image.crop(frame, { x = x, y = y, width = w, height = h, flip_y = true })
        local t_crop = system.millis() - t0
        assert_info(crop, w, h, "RGBP", w * h * 2, "crop rgb")

        local gray_w = math.min(96, w)
        local gray_h = math.min(96, h)
        t0 = system.millis()
        local gray = image.crop(frame, { x = x, y = y, width = gray_w, height = gray_h, format = image.GRAY8 })
        local t_gray = system.millis() - t0
        assert_info(gray, gray_w, gray_h, "GREY", gray_w * gray_h, "crop gray")

        frames = frames + 1
        crop_sum = crop_sum + t_crop
        gray_sum = gray_sum + t_gray

        if frames % RELEASE_CHECK_EVERY_N == 0 then
            frame:release()
            assert_true(crop:info().valid == true, "cropped RGB view should survive source release")
            assert_true(gray:info().valid == true, "cropped gray view should survive source release")
            release_checks = release_checks + 1
        end

        display.begin_frame({ clear = true, color = "black" })
        display.fill_rect(0, 0, display.width, overlay_h, { r = 24, g = 24, b = 24 })
        display.draw_text(6, 4, string.format("image.crop  frame=%d  left=%ds", frames, remaining_s),
            { color = "white", font_size = 14 })
        display.draw_text(6, 24, string.format("crop=%dms  gray=%dms  release_checks=%d",
            t_crop, t_gray, release_checks), { color = "white", font_size = 12 })
        display.draw_image(0, overlay_h, crop, {
            mode = "fit",
            width = display.width,
            height = display.height - overlay_h,
        })
        display.present()
        display.end_frame()

        crop:release()
        gray:release()

        if frames == 1 or frames % 10 == 0 then
            print(string.format("%s frame=%d crop=%dms gray=%dms", TAG, frames, t_crop, t_gray))
        end

        if FRAME_INTERVAL_MS > 0 then
            delay.delay_ms(FRAME_INTERVAL_MS)
        end
    end

    assert_true(frames > 0, "no frames captured")

    local crop_avg = crop_sum / frames
    local gray_avg = gray_sum / frames

    display.begin_frame({ clear = true, color = "black" })
    display.draw_text_aligned(0, 0, display.width, display.height,
        string.format("Crop PASS\nframes=%d\ncrop=%.1fms\ngray=%.1fms", frames, crop_avg, gray_avg),
        { color = "white", font_size = 18, align = "center", valign = "middle" })
    display.present()
    display.end_frame()

    print(string.format("%s PASS frames=%d crop_avg=%.1fms gray_avg=%.1fms release_checks=%d",
        TAG, frames, crop_avg, gray_avg, release_checks))
end, debug.traceback)

cleanup()

if not run_ok then
    error(run_err)
end
