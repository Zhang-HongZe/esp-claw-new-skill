/*
 * SPDX-FileCopyrightText: 2026 Espressif Systems (Shanghai) CO LTD
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include "lua_module_motion_detect.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "cap_lua.h"
#include "esp_err.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "lauxlib.h"
#include "lua_image.h"

#define LUA_MODULE_MOTION_DETECT_NAME "motion_detect"
#define LUA_MOTION_DETECT_MT "motion_detect.detector"

#define MOTION_DEFAULT_PIXEL_DIFF_THRESHOLD 24
#define MOTION_DEFAULT_ACTIVE_PIXEL_PERCENT 5
#define MOTION_DEFAULT_CONFIRM_FRAMES 2
#define MOTION_DEFAULT_HOLD_FRAMES 3
#define MOTION_DEFAULT_BLOCK_SIZE 4
#define MOTION_DEFAULT_BLOCK_HIT_PIXELS 5
#define MOTION_DEFAULT_BOX_PADDING 2
#define MOTION_DEFAULT_BOX_DEADBAND 2
#define MOTION_DEFAULT_BOX_SNAP_THRESHOLD 24

static const char *TAG = "lua_motion_detect";

typedef struct {
    int roi_x;
    int roi_y;
    int roi_width;
    int roi_height;
    int pixel_diff_threshold;
    int active_pixel_percent;
    int confirm_frames;
    int hold_frames;
    int block_size;
    int block_hit_pixels;
    int box_padding;
    int box_deadband;
    int box_snap_threshold;
} motion_detect_config_t;

typedef struct {
    uint32_t positive_frames;
    uint32_t hold_frames;
    bool alert_active;
    bool has_box;
    int x1;
    int y1;
    int x2;
    int y2;
} motion_detect_state_t;

typedef enum {
    MOTION_EVENT_NONE = 0,
    MOTION_EVENT_ACTIVATED,
    MOTION_EVENT_CLEARED,
} motion_event_t;

typedef struct {
    bool detected;
    bool has_box;
    uint32_t active_pixels;
    uint32_t threshold_pixels;
    int x1;
    int y1;
    int x2;
    int y2;
} motion_detect_result_t;

typedef struct {
    motion_detect_config_t config;
    motion_detect_state_t state;
    uint8_t *prev_luma;
    uint8_t *block_counts;
    size_t prev_luma_size;
    size_t block_count;
    int frame_width;
    int frame_height;
    bool has_previous;
} lua_motion_detector_t;

static void motion_config_set_defaults(motion_detect_config_t *config)
{
    memset(config, 0, sizeof(*config));
    config->roi_x = 0;
    config->roi_y = 0;
    config->roi_width = 0;
    config->roi_height = 0;
    config->pixel_diff_threshold = MOTION_DEFAULT_PIXEL_DIFF_THRESHOLD;
    config->active_pixel_percent = MOTION_DEFAULT_ACTIVE_PIXEL_PERCENT;
    config->confirm_frames = MOTION_DEFAULT_CONFIRM_FRAMES;
    config->hold_frames = MOTION_DEFAULT_HOLD_FRAMES;
    config->block_size = MOTION_DEFAULT_BLOCK_SIZE;
    config->block_hit_pixels = MOTION_DEFAULT_BLOCK_HIT_PIXELS;
    config->box_padding = MOTION_DEFAULT_BOX_PADDING;
    config->box_deadband = MOTION_DEFAULT_BOX_DEADBAND;
    config->box_snap_threshold = MOTION_DEFAULT_BOX_SNAP_THRESHOLD;
}

static bool motion_get_table_integer(lua_State *L, int table_idx, const char *name, int *out)
{
    bool ok = false;

    lua_getfield(L, table_idx, name);
    if (lua_isinteger(L, -1)) {
        *out = (int)lua_tointeger(L, -1);
        ok = true;
    } else if (lua_isnumber(L, -1)) {
        *out = (int)lua_tonumber(L, -1);
        ok = true;
    }
    lua_pop(L, 1);
    return ok;
}

static void motion_parse_roi(lua_State *L, int opts_idx, motion_detect_config_t *config)
{
    lua_getfield(L, opts_idx, "roi");
    if (!lua_isnil(L, -1)) {
        luaL_checktype(L, -1, LUA_TTABLE);
        motion_get_table_integer(L, -1, "x", &config->roi_x);
        motion_get_table_integer(L, -1, "y", &config->roi_y);
        motion_get_table_integer(L, -1, "width", &config->roi_width);
        motion_get_table_integer(L, -1, "height", &config->roi_height);
    }
    lua_pop(L, 1);

    motion_get_table_integer(L, opts_idx, "roi_x", &config->roi_x);
    motion_get_table_integer(L, opts_idx, "roi_y", &config->roi_y);
    motion_get_table_integer(L, opts_idx, "roi_width", &config->roi_width);
    motion_get_table_integer(L, opts_idx, "roi_height", &config->roi_height);
}

static void motion_parse_config(lua_State *L, int opts_idx, motion_detect_config_t *config)
{
    if (opts_idx <= 0 || lua_isnoneornil(L, opts_idx)) {
        return;
    }
    luaL_checktype(L, opts_idx, LUA_TTABLE);

    motion_parse_roi(L, opts_idx, config);
    motion_get_table_integer(L, opts_idx, "pixel_diff_threshold", &config->pixel_diff_threshold);
    motion_get_table_integer(L, opts_idx, "active_pixel_percent", &config->active_pixel_percent);
    motion_get_table_integer(L, opts_idx, "confirm_frames", &config->confirm_frames);
    motion_get_table_integer(L, opts_idx, "hold_frames", &config->hold_frames);
    motion_get_table_integer(L, opts_idx, "block_size", &config->block_size);
    motion_get_table_integer(L, opts_idx, "block_hit_pixels", &config->block_hit_pixels);
    motion_get_table_integer(L, opts_idx, "box_padding", &config->box_padding);
    motion_get_table_integer(L, opts_idx, "box_deadband", &config->box_deadband);
    motion_get_table_integer(L, opts_idx, "box_snap_threshold", &config->box_snap_threshold);
}

static int motion_validate_config(lua_State *L, const motion_detect_config_t *config)
{
    if (config->pixel_diff_threshold < 0 || config->pixel_diff_threshold > 255) {
        return luaL_error(L, "motion_detect pixel_diff_threshold must be in [0, 255]");
    }
    if (config->active_pixel_percent < 1 || config->active_pixel_percent > 100) {
        return luaL_error(L, "motion_detect active_pixel_percent must be in [1, 100]");
    }
    if (config->confirm_frames < 1) {
        return luaL_error(L, "motion_detect confirm_frames must be >= 1");
    }
    if (config->hold_frames < 0) {
        return luaL_error(L, "motion_detect hold_frames must be >= 0");
    }
    if (config->block_size < 1 || config->block_size > 255) {
        return luaL_error(L, "motion_detect block_size must be in [1, 255]");
    }
    if (config->block_hit_pixels < 1 || config->block_hit_pixels > 255) {
        return luaL_error(L, "motion_detect block_hit_pixels must be in [1, 255]");
    }
    if (config->box_padding < 0 || config->box_deadband < 0 || config->box_snap_threshold < 0) {
        return luaL_error(L, "motion_detect box padding/deadband/snap values must be >= 0");
    }
    return LUA_OK;
}

static lua_motion_detector_t *motion_check_detector(lua_State *L, int index)
{
    return (lua_motion_detector_t *)luaL_checkudata(L, index, LUA_MOTION_DETECT_MT);
}

static void *motion_alloc(size_t bytes)
{
    void *ptr = heap_caps_malloc(bytes, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (ptr == NULL) {
        ptr = heap_caps_malloc(bytes, MALLOC_CAP_8BIT);
    }
    return ptr;
}

static void motion_detector_release_buffers(lua_motion_detector_t *detector)
{
    heap_caps_free(detector->prev_luma);
    heap_caps_free(detector->block_counts);
    detector->prev_luma = NULL;
    detector->block_counts = NULL;
    detector->prev_luma_size = 0;
    detector->block_count = 0;
    detector->frame_width = 0;
    detector->frame_height = 0;
    detector->has_previous = false;
}

static void motion_detector_reset_state(lua_motion_detector_t *detector)
{
    memset(&detector->state, 0, sizeof(detector->state));
    detector->has_previous = false;
    if (detector->prev_luma != NULL && detector->prev_luma_size > 0) {
        memset(detector->prev_luma, 0, detector->prev_luma_size);
    }
    if (detector->block_counts != NULL && detector->block_count > 0) {
        memset(detector->block_counts, 0, detector->block_count);
    }
}

static int motion_abs_int(int value)
{
    return value < 0 ? -value : value;
}

static int motion_smooth_box_edge(int current, int target, int deadband, int snap_threshold)
{
    int diff = target - current;

    if (motion_abs_int(diff) <= deadband) {
        return current;
    }
    if (motion_abs_int(diff) >= snap_threshold) {
        return target;
    }
    if (diff > 0) {
        return current + (diff + 1) / 2;
    }
    return current + (diff - 1) / 2;
}

static void motion_update_display_box(lua_motion_detector_t *detector,
                                      const motion_detect_result_t *result,
                                      const motion_detect_config_t *config)
{
    if (!detector->state.has_box) {
        detector->state.has_box = true;
        detector->state.x1 = result->x1;
        detector->state.y1 = result->y1;
        detector->state.x2 = result->x2;
        detector->state.y2 = result->y2;
        return;
    }

    detector->state.x1 = motion_smooth_box_edge(detector->state.x1, result->x1,
                                                config->box_deadband, config->box_snap_threshold);
    detector->state.y1 = motion_smooth_box_edge(detector->state.y1, result->y1,
                                                config->box_deadband, config->box_snap_threshold);
    detector->state.x2 = motion_smooth_box_edge(detector->state.x2, result->x2,
                                                config->box_deadband, config->box_snap_threshold);
    detector->state.y2 = motion_smooth_box_edge(detector->state.y2, result->y2,
                                                config->box_deadband, config->box_snap_threshold);
}

static bool motion_state_update(lua_motion_detector_t *detector, bool motion_detected,
                                const motion_detect_config_t *config, motion_event_t *event_out)
{
    bool alert_active = false;

    if (event_out != NULL) {
        *event_out = MOTION_EVENT_NONE;
    }

    if (motion_detected) {
        if (detector->state.positive_frames < (uint32_t)config->confirm_frames) {
            detector->state.positive_frames++;
        }
        if (detector->state.positive_frames >= (uint32_t)config->confirm_frames) {
            detector->state.hold_frames = (uint32_t)config->hold_frames;
            alert_active = true;
        }
    } else {
        detector->state.positive_frames = 0;
        if (detector->state.hold_frames > 0) {
            detector->state.hold_frames--;
            alert_active = true;
        }
    }

    if (alert_active != detector->state.alert_active) {
        detector->state.alert_active = alert_active;
        if (event_out != NULL) {
            *event_out = alert_active ? MOTION_EVENT_ACTIVATED : MOTION_EVENT_CLEARED;
        }
    } else {
        detector->state.alert_active = alert_active;
    }

    return alert_active;
}

static inline uint8_t motion_rgb565_to_luma8(uint16_t pixel)
{
    uint8_t g6 = (uint8_t)((pixel >> 5) & 0x3f);
    return (uint8_t)((g6 << 2) | (g6 >> 4));
}

static void motion_store_luma_roi(const uint16_t *src, uint8_t *dst,
                                  int frame_width, int roi_x, int roi_y,
                                  int roi_width, int roi_height)
{
    for (int y = 0; y < roi_height; y++) {
        size_t frame_row = (size_t)(roi_y + y) * (size_t)frame_width + (size_t)roi_x;
        size_t roi_row = (size_t)y * (size_t)roi_width;
        for (int x = 0; x < roi_width; x++) {
            dst[roi_row + (size_t)x] = motion_rgb565_to_luma8(src[frame_row + (size_t)x]);
        }
    }
}

static motion_detect_result_t motion_detect_frame(const uint16_t *cur,
                                                  uint8_t *prev_luma,
                                                  uint8_t *block_counts,
                                                  int frame_width,
                                                  const motion_detect_config_t *config)
{
    motion_detect_result_t result = {0};
    const int roi_x = config->roi_x;
    const int roi_y = config->roi_y;
    const int roi_width = config->roi_width;
    const int roi_height = config->roi_height;
    const int blocks_x = (roi_width + config->block_size - 1) / config->block_size;
    const int blocks_y = (roi_height + config->block_size - 1) / config->block_size;
    const uint32_t total = (uint32_t)roi_width * (uint32_t)roi_height;
    uint32_t threshold = (total * (uint32_t)config->active_pixel_percent) / 100U;

    if (threshold == 0) {
        threshold = 1;
    }
    result.threshold_pixels = threshold;
    memset(block_counts, 0, (size_t)blocks_x * (size_t)blocks_y);

    result.x1 = roi_x + roi_width - 1;
    result.y1 = roi_y + roi_height - 1;
    result.x2 = roi_x;
    result.y2 = roi_y;

    for (int y = 0; y < roi_height; y++) {
        size_t frame_row = (size_t)(roi_y + y) * (size_t)frame_width + (size_t)roi_x;
        size_t roi_row = (size_t)y * (size_t)roi_width;
        size_t block_row = (size_t)(y / config->block_size) * (size_t)blocks_x;
        for (int x = 0; x < roi_width; x++) {
            size_t roi_index = roi_row + (size_t)x;
            uint8_t luma = motion_rgb565_to_luma8(cur[frame_row + (size_t)x]);
            int diff = abs((int)luma - (int)prev_luma[roi_index]);
            prev_luma[roi_index] = luma;

            if (diff > config->pixel_diff_threshold) {
                size_t block_index = block_row + (size_t)(x / config->block_size);
                if (block_counts[block_index] < UINT8_MAX) {
                    block_counts[block_index]++;
                }
            }
        }
    }

    for (int by = 0; by < blocks_y; by++) {
        int block_y = by * config->block_size;
        int block_h = roi_height - block_y;
        if (block_h > config->block_size) {
            block_h = config->block_size;
        }

        for (int bx = 0; bx < blocks_x; bx++) {
            int block_x = bx * config->block_size;
            int block_w = roi_width - block_x;
            if (block_w > config->block_size) {
                block_w = config->block_size;
            }

            if (block_counts[(size_t)by * (size_t)blocks_x + (size_t)bx] < config->block_hit_pixels) {
                continue;
            }

            result.active_pixels += (uint32_t)block_w * (uint32_t)block_h;
            result.has_box = true;

            int block_x1 = roi_x + block_x;
            int block_y1 = roi_y + block_y;
            int block_x2 = block_x1 + block_w - 1;
            int block_y2 = block_y1 + block_h - 1;

            if (block_x1 < result.x1) {
                result.x1 = block_x1;
            }
            if (block_y1 < result.y1) {
                result.y1 = block_y1;
            }
            if (block_x2 > result.x2) {
                result.x2 = block_x2;
            }
            if (block_y2 > result.y2) {
                result.y2 = block_y2;
            }
        }
    }

    result.detected = result.active_pixels > threshold;
    if (!result.detected || !result.has_box) {
        result.has_box = false;
        return result;
    }

    result.x1 -= config->box_padding;
    result.y1 -= config->box_padding;
    result.x2 += config->box_padding;
    result.y2 += config->box_padding;

    if (result.x1 < roi_x) {
        result.x1 = roi_x;
    }
    if (result.y1 < roi_y) {
        result.y1 = roi_y;
    }
    if (result.x2 >= roi_x + roi_width) {
        result.x2 = roi_x + roi_width - 1;
    }
    if (result.y2 >= roi_y + roi_height) {
        result.y2 = roi_y + roi_height - 1;
    }
    return result;
}

static esp_err_t motion_normalize_config(motion_detect_config_t *config, int frame_width, int frame_height)
{
    if (config->roi_width <= 0) {
        config->roi_width = frame_width;
    }
    if (config->roi_height <= 0) {
        config->roi_height = frame_height;
    }
    if (config->roi_x < 0 || config->roi_y < 0 ||
        config->roi_width <= 0 || config->roi_height <= 0 ||
        config->roi_x + config->roi_width > frame_width ||
        config->roi_y + config->roi_height > frame_height) {
        return ESP_ERR_INVALID_ARG;
    }
    if (config->block_hit_pixels > config->block_size * config->block_size) {
        return ESP_ERR_INVALID_ARG;
    }
    return ESP_OK;
}

static bool motion_config_buffers_match(const lua_motion_detector_t *detector,
                                        const motion_detect_config_t *config,
                                        int frame_width, int frame_height)
{
    if (detector->prev_luma == NULL || detector->block_counts == NULL) {
        return false;
    }
    if (detector->frame_width != frame_width || detector->frame_height != frame_height) {
        return false;
    }
    if (detector->config.roi_x != config->roi_x ||
        detector->config.roi_y != config->roi_y ||
        detector->config.roi_width != config->roi_width ||
        detector->config.roi_height != config->roi_height ||
        detector->config.block_size != config->block_size) {
        return false;
    }
    return true;
}

static esp_err_t motion_detector_prepare(lua_motion_detector_t *detector,
                                         const motion_detect_config_t *config,
                                         int frame_width, int frame_height)
{
    size_t luma_size = (size_t)config->roi_width * (size_t)config->roi_height;
    size_t blocks_x = (size_t)((config->roi_width + config->block_size - 1) / config->block_size);
    size_t blocks_y = (size_t)((config->roi_height + config->block_size - 1) / config->block_size);
    size_t block_count = blocks_x * blocks_y;

    if (motion_config_buffers_match(detector, config, frame_width, frame_height)) {
        detector->config = *config;
        return ESP_OK;
    }

    motion_detector_release_buffers(detector);
    detector->prev_luma = (uint8_t *)motion_alloc(luma_size);
    detector->block_counts = (uint8_t *)motion_alloc(block_count);
    if (detector->prev_luma == NULL || detector->block_counts == NULL) {
        motion_detector_release_buffers(detector);
        ESP_LOGE(TAG, "alloc buffers failed: luma=%zu blocks=%zu", luma_size, block_count);
        return ESP_ERR_NO_MEM;
    }

    detector->prev_luma_size = luma_size;
    detector->block_count = block_count;
    detector->frame_width = frame_width;
    detector->frame_height = frame_height;
    detector->config = *config;
    motion_detector_reset_state(detector);
    return ESP_OK;
}

static const char *motion_event_name(motion_event_t event)
{
    switch (event) {
    case MOTION_EVENT_ACTIVATED:
        return "activated";
    case MOTION_EVENT_CLEARED:
        return "cleared";
    case MOTION_EVENT_NONE:
    default:
        return "none";
    }
}

static void motion_push_box(lua_State *L, int x1, int y1, int x2, int y2)
{
    lua_newtable(L);
    lua_pushinteger(L, x1);
    lua_setfield(L, -2, "x1");
    lua_pushinteger(L, y1);
    lua_setfield(L, -2, "y1");
    lua_pushinteger(L, x2);
    lua_setfield(L, -2, "x2");
    lua_pushinteger(L, y2);
    lua_setfield(L, -2, "y2");
    lua_pushinteger(L, x1);
    lua_setfield(L, -2, "left");
    lua_pushinteger(L, y1);
    lua_setfield(L, -2, "top");
    lua_pushinteger(L, x2);
    lua_setfield(L, -2, "right");
    lua_pushinteger(L, y2);
    lua_setfield(L, -2, "bottom");
    lua_pushnumber(L, ((lua_Number)x1 + (lua_Number)x2) / 2.0);
    lua_setfield(L, -2, "cx");
    lua_pushnumber(L, ((lua_Number)y1 + (lua_Number)y2) / 2.0);
    lua_setfield(L, -2, "cy");
    lua_pushinteger(L, x2 - x1 + 1);
    lua_setfield(L, -2, "width");
    lua_pushinteger(L, y2 - y1 + 1);
    lua_setfield(L, -2, "height");
}

static void motion_push_result(lua_State *L, const lua_motion_detector_t *detector,
                               const motion_detect_config_t *config,
                               const motion_detect_result_t *result,
                               bool has_previous, bool alert_active, motion_event_t event)
{
    lua_newtable(L);
    lua_pushboolean(L, has_previous);
    lua_setfield(L, -2, "has_previous");
    lua_pushboolean(L, result->detected);
    lua_setfield(L, -2, "detected");
    lua_pushboolean(L, alert_active);
    lua_setfield(L, -2, "alert_active");
    lua_pushstring(L, motion_event_name(event));
    lua_setfield(L, -2, "event");
    lua_pushinteger(L, result->active_pixels);
    lua_setfield(L, -2, "active_pixels");
    lua_pushinteger(L, result->threshold_pixels);
    lua_setfield(L, -2, "threshold_pixels");
    lua_pushinteger(L, detector->state.positive_frames);
    lua_setfield(L, -2, "positive_frames");
    lua_pushinteger(L, detector->state.hold_frames);
    lua_setfield(L, -2, "hold_frames");

    lua_pushinteger(L, config->roi_x);
    lua_setfield(L, -2, "roi_x");
    lua_pushinteger(L, config->roi_y);
    lua_setfield(L, -2, "roi_y");
    lua_pushinteger(L, config->roi_width);
    lua_setfield(L, -2, "roi_width");
    lua_pushinteger(L, config->roi_height);
    lua_setfield(L, -2, "roi_height");

    lua_pushboolean(L, result->has_box);
    lua_setfield(L, -2, "has_box");
    if (result->has_box) {
        motion_push_box(L, result->x1, result->y1, result->x2, result->y2);
        lua_setfield(L, -2, "raw_box");
    }

    lua_pushboolean(L, detector->state.has_box);
    lua_setfield(L, -2, "has_display_box");
    if (detector->state.has_box) {
        motion_push_box(L, detector->state.x1, detector->state.y1,
                        detector->state.x2, detector->state.y2);
        lua_setfield(L, -2, "box");
    }
}

static int motion_detector_detect_impl(lua_State *L, lua_motion_detector_t *detector,
                                       int frame_index, int opts_idx)
{
    lua_image_view_t view = {0};
    motion_detect_config_t config = detector->config;
    if (opts_idx > 0 && !lua_isnoneornil(L, opts_idx)) {
        motion_parse_config(L, opts_idx, &config);
    }
    motion_validate_config(L, &config);

    esp_err_t err = lua_image_require_format(L, frame_index, LUA_IMAGE_FORMAT_RGB565LE, &view);
    if (err != ESP_OK) {
        return luaL_error(L, "motion_detect expects an RGB565-capable image.frame: %s", esp_err_to_name(err));
    }

    if (motion_normalize_config(&config, view.width, view.height) != ESP_OK) {
        lua_image_release_view(&view);
        return luaL_error(L, "motion_detect invalid ROI or block_hit_pixels");
    }
    if (motion_detector_prepare(detector, &config, view.width, view.height) != ESP_OK) {
        lua_image_release_view(&view);
        return luaL_error(L, "motion_detect prepare failed");
    }

    const uint16_t *pixels = (const uint16_t *)view.data;
    bool has_previous = detector->has_previous;
    motion_detect_result_t result = {0};
    motion_event_t event = MOTION_EVENT_NONE;
    bool alert_active = detector->state.alert_active;

    if (!has_previous) {
        motion_store_luma_roi(pixels, detector->prev_luma, view.width,
                              config.roi_x, config.roi_y, config.roi_width, config.roi_height);
        detector->has_previous = true;
        result.threshold_pixels = ((uint32_t)config.roi_width * (uint32_t)config.roi_height *
                                   (uint32_t)config.active_pixel_percent) / 100U;
        if (result.threshold_pixels == 0) {
            result.threshold_pixels = 1;
        }
    } else {
        result = motion_detect_frame(pixels, detector->prev_luma, detector->block_counts,
                                     view.width, &config);
        alert_active = motion_state_update(detector, result.detected, &config, &event);
        if (result.detected && result.has_box) {
            motion_update_display_box(detector, &result, &config);
        } else if (event == MOTION_EVENT_CLEARED) {
            detector->state.has_box = false;
        }
    }

    motion_push_result(L, detector, &config, &result, has_previous, alert_active, event);
    lua_image_release_view(&view);
    return 1;
}

static int motion_detector_new(lua_State *L)
{
    lua_motion_detector_t *detector = (lua_motion_detector_t *)lua_newuserdata(L, sizeof(*detector));
    memset(detector, 0, sizeof(*detector));
    motion_config_set_defaults(&detector->config);
    if (!lua_isnoneornil(L, 1)) {
        motion_parse_config(L, 1, &detector->config);
    }
    motion_validate_config(L, &detector->config);

    luaL_getmetatable(L, LUA_MOTION_DETECT_MT);
    lua_setmetatable(L, -2);
    return 1;
}

static int motion_detector_detect(lua_State *L)
{
    lua_motion_detector_t *detector = motion_check_detector(L, 1);
    return motion_detector_detect_impl(L, detector, 2, 3);
}

static int motion_detector_reset(lua_State *L)
{
    lua_motion_detector_t *detector = motion_check_detector(L, 1);
    motion_detector_reset_state(detector);
    return 0;
}

static int motion_detector_close(lua_State *L)
{
    lua_motion_detector_t *detector = motion_check_detector(L, 1);
    motion_detector_release_buffers(detector);
    memset(&detector->state, 0, sizeof(detector->state));
    return 0;
}

static int motion_detector_gc(lua_State *L)
{
    lua_motion_detector_t *detector = (lua_motion_detector_t *)luaL_checkudata(L, 1, LUA_MOTION_DETECT_MT);
    motion_detector_release_buffers(detector);
    return 0;
}

static lua_motion_detector_t s_default_detector;
static bool s_default_detector_initialized;

static lua_motion_detector_t *motion_default_detector(void)
{
    if (!s_default_detector_initialized) {
        memset(&s_default_detector, 0, sizeof(s_default_detector));
        motion_config_set_defaults(&s_default_detector.config);
        s_default_detector_initialized = true;
    }
    return &s_default_detector;
}

static int motion_module_detect(lua_State *L)
{
    lua_motion_detector_t *detector = motion_default_detector();
    return motion_detector_detect_impl(L, detector, 1, 2);
}

static int motion_module_reset(lua_State *L)
{
    (void)L;
    lua_motion_detector_t *detector = motion_default_detector();
    motion_detector_reset_state(detector);
    return 0;
}

static void motion_register_metatable(lua_State *L)
{
    if (luaL_newmetatable(L, LUA_MOTION_DETECT_MT)) {
        static const luaL_Reg methods[] = {
            {"detect", motion_detector_detect},
            {"reset", motion_detector_reset},
            {"close", motion_detector_close},
            {NULL, NULL},
        };
        static const luaL_Reg metamethods[] = {
            {"__gc", motion_detector_gc},
            {NULL, NULL},
        };

        lua_newtable(L);
        luaL_setfuncs(L, methods, 0);
        lua_setfield(L, -2, "__index");
        luaL_setfuncs(L, metamethods, 0);
    }
    lua_pop(L, 1);
}

int luaopen_motion_detect(lua_State *L)
{
    static const luaL_Reg funcs[] = {
        {"new", motion_detector_new},
        {"detect", motion_module_detect},
        {"reset", motion_module_reset},
        {NULL, NULL},
    };

    motion_register_metatable(L);
    lua_newtable(L);
    luaL_setfuncs(L, funcs, 0);
    return 1;
}

esp_err_t lua_module_motion_detect_register(void)
{
    return cap_lua_register_module(LUA_MODULE_MOTION_DETECT_NAME, luaopen_motion_detect);
}
