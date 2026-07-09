/*
 * SPDX-FileCopyrightText: 2026 Espressif Systems (Shanghai) CO LTD
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include "lua_module_vision.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <string>
#include <vector>

#include "dl_image.hpp"
#include "esp_err.h"
#include "esp_log.h"

extern "C" {
#include "lauxlib.h"
#include "lua_image.h"
}

static const char *TAG = "lua_color_detect";

typedef struct {
    int source_x;
    int source_y;
    int source_width;
    int source_height;
    int min_pixels;
    int max_blob_pixels;
    std::array<uint8_t, 3> hsv_min;
    std::array<uint8_t, 3> hsv_max;
} lua_color_detect_config_t;

typedef struct {
    bool found;
    int pixels;
    int left;
    int top;
    int right;
    int bottom;
} lua_color_detect_box_t;

static bool lua_color_detect_get_integer_field(lua_State *L, int table_idx, const char *name, lua_Integer *out)
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

static bool lua_color_detect_get_number_field(lua_State *L, int table_idx, const char *name, lua_Number *out)
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

static uint8_t lua_color_detect_sv_to_u8(lua_Number value)
{
    if (value <= 1.0) {
        value *= 255.0;
    }
    value = std::max<lua_Number>(0.0, std::min<lua_Number>(255.0, value));
    return static_cast<uint8_t>(std::lround(value));
}

static esp_err_t lua_color_detect_parse_source(lua_State *L, int opts_idx, lua_color_detect_config_t *config)
{
    lua_Integer integer_value = 0;

    lua_getfield(L, opts_idx, "source");
    if (!lua_istable(L, -1)) {
        lua_pop(L, 1);
        return ESP_OK;
    }

    int source_idx = lua_gettop(L);
    if (lua_color_detect_get_integer_field(L, source_idx, "x", &integer_value)) {
        config->source_x = static_cast<int>(integer_value);
    }
    if (lua_color_detect_get_integer_field(L, source_idx, "y", &integer_value)) {
        config->source_y = static_cast<int>(integer_value);
    }
    if (lua_color_detect_get_integer_field(L, source_idx, "width", &integer_value)) {
        config->source_width = static_cast<int>(integer_value);
    }
    if (lua_color_detect_get_integer_field(L, source_idx, "height", &integer_value)) {
        config->source_height = static_cast<int>(integer_value);
    }

    lua_pop(L, 1);
    return ESP_OK;
}

static esp_err_t lua_color_detect_parse_config(lua_State *L,
                                               int opts_idx,
                                               int frame_width,
                                               int frame_height,
                                               lua_color_detect_config_t *config)
{
    lua_Integer integer_value = 0;
    lua_Number number_value = 0;

    config->source_x = 0;
    config->source_y = 0;
    config->source_width = frame_width;
    config->source_height = frame_height;
    config->min_pixels = 250;
    config->max_blob_pixels = 0;
    config->hsv_min = {50, 80, 50};
    config->hsv_max = {88, 255, 255};

    if (opts_idx > 0 && lua_istable(L, opts_idx)) {
        opts_idx = lua_absindex(L, opts_idx);
        lua_color_detect_parse_source(L, opts_idx, config);
        if (lua_color_detect_get_integer_field(L, opts_idx, "min_pixels", &integer_value)) {
            config->min_pixels = static_cast<int>(integer_value);
        }
        if (lua_color_detect_get_integer_field(L, opts_idx, "max_blob_pixels", &integer_value) ||
            lua_color_detect_get_integer_field(L, opts_idx, "max_pixels", &integer_value)) {
            config->max_blob_pixels = static_cast<int>(integer_value);
        }
        if (lua_color_detect_get_integer_field(L, opts_idx, "h_min", &integer_value)) {
            config->hsv_min[0] = static_cast<uint8_t>(integer_value);
        }
        if (lua_color_detect_get_integer_field(L, opts_idx, "h_max", &integer_value)) {
            config->hsv_max[0] = static_cast<uint8_t>(integer_value);
        }
        if (lua_color_detect_get_number_field(L, opts_idx, "s_min", &number_value)) {
            config->hsv_min[1] = lua_color_detect_sv_to_u8(number_value);
        }
        if (lua_color_detect_get_number_field(L, opts_idx, "s_max", &number_value)) {
            config->hsv_max[1] = lua_color_detect_sv_to_u8(number_value);
        }
        if (lua_color_detect_get_number_field(L, opts_idx, "v_min", &number_value)) {
            config->hsv_min[2] = lua_color_detect_sv_to_u8(number_value);
        }
        if (lua_color_detect_get_number_field(L, opts_idx, "v_max", &number_value)) {
            config->hsv_max[2] = lua_color_detect_sv_to_u8(number_value);
        }
    }

    if (config->source_width <= 0 || config->source_height <= 0 ||
        config->source_x < 0 || config->source_y < 0 ||
        config->source_x + config->source_width > frame_width ||
        config->source_y + config->source_height > frame_height ||
        config->min_pixels <= 0 ||
        config->hsv_min[0] > 180 || config->hsv_max[0] > 180 ||
        config->hsv_min[1] > config->hsv_max[1] ||
        config->hsv_min[2] > config->hsv_max[2]) {
        return ESP_ERR_INVALID_ARG;
    }

    const int source_pixels = config->source_width * config->source_height;
    if (config->max_blob_pixels <= 0) {
        config->max_blob_pixels = source_pixels * 35 / 100;
    }
    if (config->max_blob_pixels <= 0 || config->max_blob_pixels >= source_pixels) {
        config->max_blob_pixels = source_pixels;
    }
    if (config->min_pixels >= source_pixels) {
        return ESP_ERR_INVALID_ARG;
    }

    return ESP_OK;
}

static lua_color_detect_box_t lua_color_detect_find_largest_component(const uint8_t *mask,
                                                                      int width,
                                                                      int height,
                                                                      int min_pixels,
                                                                      int max_blob_pixels)
{
    static const int neighbor_dx[] = {-1, 0, 1, -1, 1, -1, 0, 1};
    static const int neighbor_dy[] = {-1, -1, -1, 0, 0, 1, 1, 1};
    const int pixel_count = width * height;
    std::vector<uint8_t> visited(static_cast<size_t>(pixel_count), 0);
    std::vector<int> queue;
    queue.reserve(static_cast<size_t>(std::min(pixel_count, max_blob_pixels + 1)));

    lua_color_detect_box_t best = {
        .found = false,
        .pixels = 0,
        .left = 0,
        .top = 0,
        .right = -1,
        .bottom = -1,
    };

    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            const int start_idx = y * width + x;
            if (mask[start_idx] == 0 || visited[start_idx]) {
                continue;
            }

            int comp_pixels = 0;
            int left = width;
            int top = height;
            int right = -1;
            int bottom = -1;
            bool too_large = false;

            queue.clear();
            queue.push_back(start_idx);
            visited[start_idx] = 1;

            for (size_t head = 0; head < queue.size(); head++) {
                const int idx = queue[head];
                const int cx = idx % width;
                const int cy = idx / width;
                comp_pixels++;
                if (comp_pixels > max_blob_pixels) {
                    too_large = true;
                    break;
                }

                left = std::min(left, cx);
                top = std::min(top, cy);
                right = std::max(right, cx);
                bottom = std::max(bottom, cy);

                for (int n = 0; n < 8; n++) {
                    const int nx = cx + neighbor_dx[n];
                    const int ny = cy + neighbor_dy[n];
                    if (nx < 0 || nx >= width || ny < 0 || ny >= height) {
                        continue;
                    }
                    const int nidx = ny * width + nx;
                    if (mask[nidx] == 0 || visited[nidx]) {
                        continue;
                    }
                    visited[nidx] = 1;
                    queue.push_back(nidx);
                }
            }

            if (too_large || comp_pixels < min_pixels || comp_pixels <= best.pixels) {
                continue;
            }

            best.found = true;
            best.pixels = comp_pixels;
            best.left = left;
            best.top = top;
            best.right = right;
            best.bottom = bottom;
        }
    }

    return best;
}

static void lua_color_detect_push_empty(lua_State *L, const lua_color_detect_config_t *config, int frame_width, int frame_height)
{
    lua_newtable(L);
    lua_pushinteger(L, 0);
    lua_setfield(L, -2, "count");
    lua_pushboolean(L, false);
    lua_setfield(L, -2, "detected");
    lua_pushinteger(L, frame_width);
    lua_setfield(L, -2, "width");
    lua_pushinteger(L, frame_height);
    lua_setfield(L, -2, "height");
    lua_pushinteger(L, config->source_x);
    lua_setfield(L, -2, "source_x");
    lua_pushinteger(L, config->source_y);
    lua_setfield(L, -2, "source_y");
    lua_pushinteger(L, config->source_width);
    lua_setfield(L, -2, "source_width");
    lua_pushinteger(L, config->source_height);
    lua_setfield(L, -2, "source_height");
}

static void lua_color_detect_push_result(lua_State *L,
                                         const lua_color_detect_config_t *config,
                                         const lua_color_detect_box_t *box,
                                         int frame_width,
                                         int frame_height)
{
    const int left = config->source_x + box->left;
    const int top = config->source_y + box->top;
    const int right = config->source_x + box->right;
    const int bottom = config->source_y + box->bottom;
    const int box_w = right - left + 1;
    const int box_h = bottom - top + 1;
    const double cx = ((double)left + (double)right) * 0.5;
    const double cy = ((double)top + (double)bottom) * 0.5;

    lua_newtable(L);
    lua_pushinteger(L, 1);
    lua_setfield(L, -2, "count");
    lua_pushboolean(L, true);
    lua_setfield(L, -2, "detected");
    lua_pushinteger(L, box->pixels);
    lua_setfield(L, -2, "pixels");
    lua_pushinteger(L, frame_width);
    lua_setfield(L, -2, "width");
    lua_pushinteger(L, frame_height);
    lua_setfield(L, -2, "height");
    lua_pushinteger(L, 0);
    lua_setfield(L, -2, "category");
    lua_pushnumber(L, 1.0);
    lua_setfield(L, -2, "score");

    lua_pushinteger(L, config->source_x);
    lua_setfield(L, -2, "source_x");
    lua_pushinteger(L, config->source_y);
    lua_setfield(L, -2, "source_y");
    lua_pushinteger(L, config->source_width);
    lua_setfield(L, -2, "source_width");
    lua_pushinteger(L, config->source_height);
    lua_setfield(L, -2, "source_height");

    lua_pushinteger(L, left);
    lua_setfield(L, -2, "left");
    lua_pushinteger(L, top);
    lua_setfield(L, -2, "top");
    lua_pushinteger(L, right);
    lua_setfield(L, -2, "right");
    lua_pushinteger(L, bottom);
    lua_setfield(L, -2, "bottom");
    lua_pushinteger(L, left);
    lua_setfield(L, -2, "x");
    lua_pushinteger(L, top);
    lua_setfield(L, -2, "y");
    lua_pushinteger(L, box_w);
    lua_setfield(L, -2, "box_width");
    lua_pushinteger(L, box_h);
    lua_setfield(L, -2, "box_height");
    lua_pushnumber(L, cx);
    lua_setfield(L, -2, "cx");
    lua_pushnumber(L, cy);
    lua_setfield(L, -2, "cy");

    lua_createtable(L, 4, 0);
    lua_pushinteger(L, left);
    lua_rawseti(L, -2, 1);
    lua_pushinteger(L, top);
    lua_rawseti(L, -2, 2);
    lua_pushinteger(L, right);
    lua_rawseti(L, -2, 3);
    lua_pushinteger(L, bottom);
    lua_rawseti(L, -2, 4);
    lua_setfield(L, -2, "box");
}

static int lua_color_detect_detect(lua_State *L)
{
    lua_image_view_t view = {0};
    lua_color_detect_config_t config = {};
    esp_err_t err = lua_image_require_format(L, 1, LUA_IMAGE_FORMAT_RGB565LE, &view);
    if (err != ESP_OK) {
        return luaL_error(L, "color_detect unsupported frame: %s", esp_err_to_name(err));
    }

    err = lua_color_detect_parse_config(L, lua_istable(L, 2) ? 2 : 0, view.width, view.height, &config);
    if (err != ESP_OK) {
        lua_image_release_view(&view);
        return luaL_error(L, "invalid color_detect options");
    }

    std::vector<uint8_t> mask(static_cast<size_t>(config.source_width) * config.source_height, 0);
    dl::image::img_t src_img = {
        .data = const_cast<uint8_t *>(view.data),
        .width = static_cast<uint16_t>(view.width),
        .height = static_cast<uint16_t>(view.height),
        .pix_type = dl::image::DL_IMAGE_PIX_TYPE_RGB565LE,
    };
    dl::image::img_t mask_img = {
        .data = mask.data(),
        .width = static_cast<uint16_t>(config.source_width),
        .height = static_cast<uint16_t>(config.source_height),
        .pix_type = dl::image::DL_IMAGE_PIX_TYPE_HSV_MASK,
    };

    dl::image::ImageTransformer transformer;
    transformer.set_src_img(src_img)
        .set_dst_img(mask_img)
        .set_src_img_crop_area({
            config.source_x,
            config.source_y,
            config.source_x + config.source_width,
            config.source_y + config.source_height,
        })
        .set_hsv_thr(config.hsv_min, config.hsv_max);

    err = transformer.transform();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "ImageTransformer failed: %s", esp_err_to_name(err));
        lua_image_release_view(&view);
        return luaL_error(L, "color_detect transform failed: %s", esp_err_to_name(err));
    }

    lua_color_detect_box_t box = lua_color_detect_find_largest_component(mask.data(),
                                                                         config.source_width,
                                                                         config.source_height,
                                                                         config.min_pixels,
                                                                         config.max_blob_pixels);
    if (!box.found) {
        lua_color_detect_push_empty(L, &config, view.width, view.height);
    } else {
        lua_color_detect_push_result(L, &config, &box, view.width, view.height);
    }

    lua_image_release_view(&view);
    return 1;
}

extern "C" int luaopen_color_detect_dl(lua_State *L)
{
    static const luaL_Reg funcs[] = {
        {"detect", lua_color_detect_detect},
        {NULL, NULL},
    };
    lua_newtable(L);
    luaL_setfuncs(L, funcs, 0);
    return 1;
}
