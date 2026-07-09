/*
 * SPDX-FileCopyrightText: 2026 Espressif Systems (Shanghai) CO LTD
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include "lua_module_vision.h"

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include "cap_lua.h"
#include "esp_err.h"
#include "esp_log.h"
#include "lauxlib.h"
#include "lua.h"
#include "sdkconfig.h"

#if CONFIG_LUA_MODULE_VISION_ESPDET
#include "espdet.h"
#endif
#if CONFIG_LUA_MODULE_VISION_MOTION_DETECT || CONFIG_LUA_MODULE_VISION_COLOR_DETECT
#include "lua_image.h"
#endif
#if CONFIG_LUA_MODULE_VISION_MOTION_DETECT
#include "motion_detect.h"
#endif

#if CONFIG_LUA_MODULE_VISION_MOTION_DETECT || CONFIG_LUA_MODULE_VISION_COLOR_DETECT
static const char *LUA_IMAGE_FRAME_MT = "image.frame";

static bool lua_vision_get_field_integer(lua_State *L, int table_idx, const char *name, lua_Integer *out)
{
    bool ok = false;
    lua_getfield(L, table_idx, name);
    if (lua_isinteger(L, -1)) {
        *out = lua_tointeger(L, -1);
        ok = true;
    } else if (lua_isnumber(L, -1)) {
        *out = (lua_Integer)lua_tonumber(L, -1);
        ok = true;
    }
    lua_pop(L, 1);
    return ok;
}

static bool lua_vision_get_field_number(lua_State *L, int table_idx, const char *name, lua_Number *out)
{
    bool ok = false;
    lua_getfield(L, table_idx, name);
    if (lua_isnumber(L, -1)) {
        *out = lua_tonumber(L, -1);
        ok = true;
    }
    lua_pop(L, 1);
    return ok;
}
#endif

#if CONFIG_LUA_MODULE_VISION_MOTION_DETECT
static const char *TAG = "lua_vision";
static motion_detect_context_t s_motion_ctx;

static motion_detect_gray_frame_t lua_vision_gray_frame_from_view(const lua_image_view_t *view)
{
    motion_detect_gray_frame_t frame = {
        .data = view->data,
        .width = (uint32_t)view->width,
        .height = (uint32_t)view->height,
        .bytes = view->bytes,
    };
    return frame;
}

static void lua_motion_push_seed_result(lua_State *L, const motion_detect_config_t *config)
{
    lua_newtable(L);
    lua_pushboolean(L, false);
    lua_setfield(L, -2, "has_previous");
    lua_pushinteger(L, config->stride);
    lua_setfield(L, -2, "stride");
    lua_pushnumber(L, config->pixel_threshold);
    lua_setfield(L, -2, "pixel_threshold");
    if (config->has_moving_threshold) {
        lua_pushnumber(L, config->moving_threshold);
        lua_setfield(L, -2, "moving_threshold");
    }
}

static void lua_motion_push_compare_result(lua_State *L,
                                           const motion_detect_config_t *config,
                                           const motion_detect_result_t *result,
                                           bool has_previous)
{
    lua_newtable(L);
    lua_pushboolean(L, has_previous);
    lua_setfield(L, -2, "has_previous");
    lua_pushinteger(L, result->moving_points);
    lua_setfield(L, -2, "moving_points");
    lua_pushinteger(L, result->sample_points);
    lua_setfield(L, -2, "sample_points");
    lua_pushnumber(L, result->moving_ratio);
    lua_setfield(L, -2, "moving_ratio");
    lua_pushinteger(L, config->stride);
    lua_setfield(L, -2, "stride");
    lua_pushnumber(L, config->pixel_threshold);
    lua_setfield(L, -2, "pixel_threshold");
    if (config->has_moving_threshold) {
        lua_pushnumber(L, config->moving_threshold);
        lua_setfield(L, -2, "moving_threshold");
        lua_pushboolean(L, result->moved);
        lua_setfield(L, -2, "moved");
    }
}

static int lua_motion_parse_config(lua_State *L, int opts_idx, bool use_previous, motion_detect_config_t *config)
{
    memset(config, 0, sizeof(*config));
    config->stride = 4;
    config->pixel_threshold = 5.0 / 255.0;

    if (opts_idx > 0 && lua_istable(L, opts_idx)) {
        lua_Integer integer_value = 0;
        lua_Number number_value = 0.0;
        if (lua_vision_get_field_integer(L, opts_idx, "stride", &integer_value)) {
            config->stride = (int)integer_value;
        }
        if (lua_vision_get_field_number(L, opts_idx, "pixel_threshold", &number_value)) {
            config->pixel_threshold = number_value;
        }
        if (lua_vision_get_field_number(L, opts_idx, "moving_threshold", &number_value)) {
            config->moving_threshold = number_value;
            config->has_moving_threshold = true;
        }
    } else if (!use_previous) {
        config->stride = (int)luaL_optinteger(L, 3, config->stride);
        config->pixel_threshold = luaL_optnumber(L, 4, config->pixel_threshold);
        if (!lua_isnoneornil(L, 5)) {
            config->moving_threshold = luaL_checknumber(L, 5);
            config->has_moving_threshold = true;
        }
    }

    if (config->stride <= 0 || config->pixel_threshold < 0.0 || config->pixel_threshold > 1.0 ||
        (config->has_moving_threshold && (config->moving_threshold < 0.0 || config->moving_threshold > 1.0))) {
        ESP_LOGE(TAG, "invalid motion options: stride=%d pixel_threshold=%f moving_threshold=%f has_moving_threshold=%d",
                 config->stride, config->pixel_threshold, config->moving_threshold, config->has_moving_threshold);
        return luaL_error(L, "invalid motion options: stride must be > 0, thresholds must be in [0, 1]");
    }
    return LUA_OK;
}

/**
 * @brief Lua binding for motion_detect.detect().
 *
 * Lua input forms:
 * - motion_detect.detect(frame, opts)
 * - motion_detect.detect(frame1, frame2, opts)
 * - motion_detect.detect(frame1, frame2, stride, pixel_threshold, moving_threshold)
 */
static int lua_motion_detect_detect(lua_State *L)
{
    lua_image_view_t frame1_view = {0};
    lua_image_view_t frame2_view = {0};
    motion_detect_gray_frame_t frame1 = {0};
    motion_detect_gray_frame_t frame2 = {0};
    motion_detect_config_t config = {0};
    motion_detect_result_t result = {0};
    int opts_idx = 3;
    bool use_previous = false;
    bool has_previous = false;
    esp_err_t err;

    if (luaL_testudata(L, 2, LUA_IMAGE_FRAME_MT) != NULL) {
        opts_idx = 3;
    } else {
        use_previous = true;
        opts_idx = lua_istable(L, 2) ? 2 : 0;
    }
    lua_motion_parse_config(L, opts_idx, use_previous, &config);

    err = lua_image_require_format(L, 1, LUA_IMAGE_FORMAT_GRAY8, &frame1_view);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "motion frame1 require failed: %s", esp_err_to_name(err));
        return luaL_error(L, "motion_detect unsupported frame1: %s", esp_err_to_name(err));
    }
    frame1 = lua_vision_gray_frame_from_view(&frame1_view);

    if (luaL_testudata(L, 2, LUA_IMAGE_FRAME_MT) != NULL) {
        err = lua_image_require_format(L, 2, LUA_IMAGE_FORMAT_GRAY8, &frame2_view);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "motion frame2 require failed: %s", esp_err_to_name(err));
            lua_image_release_view(&frame1_view);
            return luaL_error(L, "motion_detect unsupported frame2: %s", esp_err_to_name(err));
        }
        frame2 = lua_vision_gray_frame_from_view(&frame2_view);
    }

    if (use_previous) {
        has_previous = motion_detect_context_has_previous(&s_motion_ctx, &frame1);
        if (!has_previous) {
            err = motion_detect_context_update(&s_motion_ctx, &frame1);
            lua_image_release_view(&frame1_view);
            if (err != ESP_OK) {
                ESP_LOGE(TAG, "motion previous-frame seed failed: %s", esp_err_to_name(err));
                return luaL_error(L, "motion_detect failed to copy previous frame");
            }
            lua_motion_push_seed_result(L, &config);
            return 1;
        }
        err = motion_detect_compare_gray(&s_motion_ctx.prev_frame, &frame1, &config, &result);
    } else {
        err = motion_detect_compare_gray(&frame1, &frame2, &config, &result);
    }

    if (err != ESP_OK) {
        ESP_LOGE(TAG, "motion_detect failed: %s", esp_err_to_name(err));
        lua_image_release_view(&frame1_view);
        lua_image_release_view(&frame2_view);
        return luaL_error(L, "motion_detect failed: %s", esp_err_to_name(err));
    }

    if (use_previous) {
        esp_err_t update_err = motion_detect_context_update(&s_motion_ctx, &frame1);
        if (update_err != ESP_OK) {
            ESP_LOGE(TAG, "motion previous-frame update failed: %s", esp_err_to_name(update_err));
            lua_image_release_view(&frame1_view);
            return luaL_error(L, "motion_detect failed to update previous frame");
        }
    }

    lua_motion_push_compare_result(L, &config, &result, has_previous);
    lua_image_release_view(&frame1_view);
    lua_image_release_view(&frame2_view);
    return 1;
}

/**
 * @brief Lua binding for motion_detect.reset().
 */
static int lua_motion_detect_reset(lua_State *L)
{
    (void)L;
    motion_detect_context_reset(&s_motion_ctx);
    return 0;
}

int luaopen_motion_detect(lua_State *L)
{
    static const luaL_Reg funcs[] = {
        {"detect", lua_motion_detect_detect},
        {"get_moving_point_number", lua_motion_detect_detect},
        {"reset", lua_motion_detect_reset},
        {NULL, NULL},
    };
    lua_newtable(L);
    luaL_setfuncs(L, funcs, 0);
    return 1;
}
#endif

#if CONFIG_LUA_MODULE_VISION_COLOR_DETECT
typedef struct {
    int stride;
    int min_pixels;
    int h_min;
    int h_max;
    double s_min;
    double v_min;
} lua_color_detect_config_t;

typedef struct {
    int left;
    int top;
    int right;
    int bottom;
    int pixels;
} lua_color_detect_result_t;

static void lua_color_detect_config_default(lua_color_detect_config_t *config)
{
    memset(config, 0, sizeof(*config));
    config->stride = 4;
    config->min_pixels = 20;
    config->h_min = 50;
    config->h_max = 88;
    config->s_min = 0.31;
    config->v_min = 0.20;
}

static void lua_color_detect_parse_config(lua_State *L, int opts_idx, lua_color_detect_config_t *config)
{
    lua_Integer integer_value = 0;
    lua_Number number_value = 0;

    lua_color_detect_config_default(config);
    if (opts_idx <= 0 || !lua_istable(L, opts_idx)) {
        return;
    }

    if (lua_vision_get_field_integer(L, opts_idx, "stride", &integer_value)) {
        config->stride = (int)integer_value;
    }
    if (lua_vision_get_field_integer(L, opts_idx, "min_pixels", &integer_value)) {
        config->min_pixels = (int)integer_value;
    }
    if (lua_vision_get_field_integer(L, opts_idx, "h_min", &integer_value)) {
        config->h_min = (int)integer_value;
    }
    if (lua_vision_get_field_integer(L, opts_idx, "h_max", &integer_value)) {
        config->h_max = (int)integer_value;
    }
    if (lua_vision_get_field_number(L, opts_idx, "s_min", &number_value)) {
        config->s_min = number_value;
    }
    if (lua_vision_get_field_number(L, opts_idx, "v_min", &number_value)) {
        config->v_min = number_value;
    }
}

static bool lua_color_detect_hue_in_range(double hue, int h_min, int h_max)
{
    if (h_min <= h_max) {
        return hue >= h_min && hue <= h_max;
    }
    return hue >= h_min || hue <= h_max;
}

static double lua_color_detect_max3(double a, double b, double c)
{
    double value = a > b ? a : b;
    return value > c ? value : c;
}

static double lua_color_detect_min3(double a, double b, double c)
{
    double value = a < b ? a : b;
    return value < c ? value : c;
}

static bool lua_color_detect_rgb_matches_green(uint8_t r, uint8_t g, uint8_t b,
                                               const lua_color_detect_config_t *config)
{
    const double rf = (double)r / 255.0;
    const double gf = (double)g / 255.0;
    const double bf = (double)b / 255.0;
    const double max_v = lua_color_detect_max3(rf, gf, bf);
    const double min_v = lua_color_detect_min3(rf, gf, bf);
    double hue = 0.0;
    double saturation = 0.0;

    if (max_v <= min_v) {
        return false;
    }

    saturation = (max_v - min_v) / max_v;
    if (saturation < config->s_min || max_v < config->v_min) {
        return false;
    }

    if (max_v == gf) {
        hue = 60.0 * ((bf - rf) / (max_v - min_v)) + 120.0;
    } else if (max_v == rf) {
        hue = 60.0 * ((gf - bf) / (max_v - min_v));
    } else {
        hue = 60.0 * ((rf - gf) / (max_v - min_v)) + 240.0;
    }

    if (hue < 0.0) {
        hue += 360.0;
    }
    hue *= 0.5;
    return lua_color_detect_hue_in_range(hue, config->h_min, config->h_max);
}

static void lua_color_detect_rgb565_to_rgb888(uint16_t pixel, uint8_t *r, uint8_t *g, uint8_t *b)
{
    uint8_t r5 = (uint8_t)((pixel >> 11) & 0x1f);
    uint8_t g6 = (uint8_t)((pixel >> 5) & 0x3f);
    uint8_t b5 = (uint8_t)(pixel & 0x1f);

    *r = (uint8_t)((r5 << 3) | (r5 >> 2));
    *g = (uint8_t)((g6 << 2) | (g6 >> 4));
    *b = (uint8_t)((b5 << 3) | (b5 >> 2));
}

static void lua_color_detect_push_empty(lua_State *L, const lua_color_detect_config_t *config,
                                        int width, int height)
{
    lua_newtable(L);
    lua_pushinteger(L, 0);
    lua_setfield(L, -2, "count");
    lua_pushboolean(L, false);
    lua_setfield(L, -2, "detected");
    lua_pushinteger(L, width);
    lua_setfield(L, -2, "width");
    lua_pushinteger(L, height);
    lua_setfield(L, -2, "height");
    lua_pushinteger(L, config->stride);
    lua_setfield(L, -2, "stride");
}

static void lua_color_detect_push_result(lua_State *L, const lua_color_detect_config_t *config,
                                         const lua_color_detect_result_t *result,
                                         int width, int height)
{
    const int box_w = result->right - result->left + 1;
    const int box_h = result->bottom - result->top + 1;
    const double cx = ((double)result->left + (double)result->right) * 0.5;
    const double cy = ((double)result->top + (double)result->bottom) * 0.5;

    lua_newtable(L);
    lua_pushinteger(L, 1);
    lua_setfield(L, -2, "count");
    lua_pushboolean(L, true);
    lua_setfield(L, -2, "detected");
    lua_pushinteger(L, result->pixels);
    lua_setfield(L, -2, "pixels");
    lua_pushinteger(L, width);
    lua_setfield(L, -2, "width");
    lua_pushinteger(L, height);
    lua_setfield(L, -2, "height");
    lua_pushinteger(L, config->stride);
    lua_setfield(L, -2, "stride");

    lua_pushinteger(L, result->left);
    lua_setfield(L, -2, "left");
    lua_pushinteger(L, result->top);
    lua_setfield(L, -2, "top");
    lua_pushinteger(L, result->right);
    lua_setfield(L, -2, "right");
    lua_pushinteger(L, result->bottom);
    lua_setfield(L, -2, "bottom");
    lua_pushinteger(L, result->left);
    lua_setfield(L, -2, "x");
    lua_pushinteger(L, result->top);
    lua_setfield(L, -2, "y");
    lua_pushinteger(L, box_w);
    lua_setfield(L, -2, "box_width");
    lua_pushinteger(L, box_h);
    lua_setfield(L, -2, "box_height");
    lua_pushnumber(L, cx);
    lua_setfield(L, -2, "cx");
    lua_pushnumber(L, cy);
    lua_setfield(L, -2, "cy");
}

static int lua_color_detect_detect(lua_State *L)
{
    lua_image_view_t view = {0};
    lua_color_detect_config_t config;
    lua_color_detect_result_t result = {
        .left = INT32_MAX,
        .top = INT32_MAX,
        .right = -1,
        .bottom = -1,
        .pixels = 0,
    };
    esp_err_t err;

    if (luaL_testudata(L, 1, LUA_IMAGE_FRAME_MT) == NULL) {
        return luaL_error(L, "color_detect.detect expects image.frame");
    }

    lua_color_detect_parse_config(L, lua_istable(L, 2) ? 2 : 0, &config);
    if (config.stride <= 0 || config.min_pixels <= 0 ||
        config.h_min < 0 || config.h_min > 180 || config.h_max < 0 || config.h_max > 180 ||
        config.s_min < 0.0 || config.s_min > 1.0 || config.v_min < 0.0 || config.v_min > 1.0) {
        return luaL_error(L, "invalid color_detect options");
    }

    err = lua_image_require_format(L, 1, LUA_IMAGE_FORMAT_RGB565LE, &view);
    if (err != ESP_OK) {
        return luaL_error(L, "color_detect unsupported frame: %s", esp_err_to_name(err));
    }

    for (int y = 0; y < view.height; y += config.stride) {
        const uint8_t *row = view.data + ((size_t)y * (size_t)view.width * 2U);
        for (int x = 0; x < view.width; x += config.stride) {
            const uint8_t *p = row + ((size_t)x * 2U);
            uint8_t r = 0;
            uint8_t g = 0;
            uint8_t b = 0;
            uint16_t pixel = (uint16_t)p[0] | ((uint16_t)p[1] << 8);

            lua_color_detect_rgb565_to_rgb888(pixel, &r, &g, &b);
            if (!lua_color_detect_rgb_matches_green(r, g, b, &config)) {
                continue;
            }
            result.pixels++;
            if (x < result.left) {
                result.left = x;
            }
            if (x > result.right) {
                result.right = x;
            }
            if (y < result.top) {
                result.top = y;
            }
            if (y > result.bottom) {
                result.bottom = y;
            }
        }
    }

    if (result.pixels < config.min_pixels || result.right < result.left || result.bottom < result.top) {
        lua_color_detect_push_empty(L, &config, view.width, view.height);
    } else {
        lua_color_detect_push_result(L, &config, &result, view.width, view.height);
    }
    lua_image_release_view(&view);
    return 1;
}

int luaopen_color_detect(lua_State *L)
{
    static const luaL_Reg funcs[] = {
        {"detect", lua_color_detect_detect},
        {NULL, NULL},
    };
    lua_newtable(L);
    luaL_setfuncs(L, funcs, 0);
    return 1;
}
#endif

esp_err_t lua_module_vision_register(void)
{
#if !CONFIG_LUA_MODULE_VISION_MOTION_DETECT && !CONFIG_LUA_MODULE_VISION_COLOR_DETECT && !CONFIG_LUA_MODULE_VISION_ESPDET
    return ESP_OK;
#else
    static const cap_lua_module_t modules[] = {
#if CONFIG_LUA_MODULE_VISION_MOTION_DETECT
        {"vision_motion_detect", luaopen_motion_detect},
#endif
#if CONFIG_LUA_MODULE_VISION_COLOR_DETECT
        {"color_detect", luaopen_color_detect},
#endif
#if CONFIG_LUA_MODULE_VISION_ESPDET
        {"espdet", luaopen_espdet},
#endif
    };
    return cap_lua_register_modules(modules, sizeof(modules) / sizeof(modules[0]));
#endif
}
