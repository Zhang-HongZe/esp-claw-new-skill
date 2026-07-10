--[[
  image_rotate.lua

  Live LCD test for image.rotate(). Each captured camera frame is rotated into
  0/90/180/270 degree views and shown in quadrants so the operator can confirm
  orientation. The script also checks RGB565 and GRAY8 metadata and verifies
  rotated frames outlive an explicit source release.
--]]

local board_manager = require("board_manager")
local camera = require("camera")
local delay = require("delay")
local display = require("display")
local image = require("image")
local system = require("system")

local TAG = "[image_rotate]"
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
    local cell_w = display.width // 2
    local cell_h = math.max(32, (display.height - overlay_h) // 2)

    print(string.format("%s start %ds cells=%dx%d", TAG, RUN_SECONDS, cell_w, cell_h))

    local start_ms = system.millis()
    local deadline_ms = start_ms + RUN_SECONDS * 1000
    local frames = 0
    local rotate_sum = 0
    local gray_sum = 0
    local release_checks = 0

    while system.millis() < deadline_ms do
        local now_ms = system.millis()
        local remaining_s = math.max(0, math.floor((deadline_ms - now_ms) / 1000))

        local frame <close> = camera.get_frame(CAPTURE_TIMEOUT_MS)
        assert_true(frame ~= nil, "camera.get_frame returned nil")

        local rgb <close> = image.convert(frame, image.RGB565)
        local rgb_info = rgb:info()
        local source_w = rgb_info.width
        local source_h = rgb_info.height
        rgb:release()

        local t0 = system.millis()
        local r0 = image.rotate(frame, { angle = 0 })
        local r90 = image.rotate(frame, { angle = 90 })
        local r180 = image.rotate(frame, { angle = 180 })
        local r270 = image.rotate(frame, { angle = 270 })
        local t_rotate = system.millis() - t0

        assert_info(r0, source_w, source_h, "RGBP", source_w * source_h * 2, "rotate 0")
        assert_info(r90, source_h, source_w, "RGBP", source_w * source_h * 2, "rotate 90")
        assert_info(r180, source_w, source_h, "RGBP", source_w * source_h * 2, "rotate 180")
        assert_info(r270, source_h, source_w, "RGBP", source_w * source_h * 2, "rotate 270")

        t0 = system.millis()
        local gray = image.rotate(frame, { angle = 90, format = image.GRAY8 })
        local t_gray = system.millis() - t0
        assert_info(gray, source_h, source_w, "GREY", source_w * source_h, "rotate gray")

        frames = frames + 1
        rotate_sum = rotate_sum + t_rotate
        gray_sum = gray_sum + t_gray

        if frames % RELEASE_CHECK_EVERY_N == 0 then
            frame:release()
            assert_true(r0:info().valid == true, "rotated 0 view should survive source release")
            assert_true(r90:info().valid == true, "rotated 90 view should survive source release")
            assert_true(r180:info().valid == true, "rotated 180 view should survive source release")
            assert_true(r270:info().valid == true, "rotated 270 view should survive source release")
            assert_true(gray:info().valid == true, "gray rotated view should survive source release")
            release_checks = release_checks + 1
        end

        display.begin_frame({ clear = true, color = "black" })
        display.fill_rect(0, 0, display.width, overlay_h, { r = 24, g = 24, b = 24 })
        display.draw_text(6, 4, string.format("image.rotate  frame=%d  left=%ds", frames, remaining_s),
            { color = "white", font_size = 14 })
        display.draw_text(6, 24, string.format("rgb set=%dms  gray90=%dms  release_checks=%d",
            t_rotate, t_gray, release_checks), { color = "white", font_size = 12 })

        display.draw_image(0, overlay_h, r0, { mode = "fit", width = cell_w, height = cell_h })
        display.draw_image(cell_w, overlay_h, r90, { mode = "fit", width = cell_w, height = cell_h })
        display.draw_image(0, overlay_h + cell_h, r180, { mode = "fit", width = cell_w, height = cell_h })
        display.draw_image(cell_w, overlay_h + cell_h, r270, { mode = "fit", width = cell_w, height = cell_h })

        display.draw_text(4, overlay_h + 2, "0", { color = "yellow", font_size = 14 })
        display.draw_text(cell_w + 4, overlay_h + 2, "90", { color = "yellow", font_size = 14 })
        display.draw_text(4, overlay_h + cell_h + 2, "180", { color = "yellow", font_size = 14 })
        display.draw_text(cell_w + 4, overlay_h + cell_h + 2, "270", { color = "yellow", font_size = 14 })

        display.present()
        display.end_frame()

        r0:release()
        r90:release()
        r180:release()
        r270:release()
        gray:release()

        if frames == 1 or frames % 10 == 0 then
            print(string.format("%s frame=%d rotate=%dms gray=%dms", TAG, frames, t_rotate, t_gray))
        end

        if FRAME_INTERVAL_MS > 0 then
            delay.delay_ms(FRAME_INTERVAL_MS)
        end
    end

    assert_true(frames > 0, "no frames captured")

    local rotate_avg = rotate_sum / frames
    local gray_avg = gray_sum / frames

    display.begin_frame({ clear = true, color = "black" })
    display.draw_text_aligned(0, 0, display.width, display.height,
        string.format("Rotate PASS\nframes=%d\nrgb set=%.1fms\ngray90=%.1fms",
            frames, rotate_avg, gray_avg),
        { color = "white", font_size = 18, align = "center", valign = "middle" })
    display.present()
    display.end_frame()

    print(string.format("%s PASS frames=%d rotate_avg=%.1fms gray_avg=%.1fms release_checks=%d",
        TAG, frames, rotate_avg, gray_avg, release_checks))
end, debug.traceback)

cleanup()

if not run_ok then
    error(run_err)
end
