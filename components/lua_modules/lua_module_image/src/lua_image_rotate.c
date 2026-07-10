/*
 * SPDX-FileCopyrightText: 2026 Espressif Systems (Shanghai) CO LTD
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include "lua_image_rotate.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "esp_heap_caps.h"
#include "esp_log.h"

#define LUA_IMAGE_ROTATE_MAX_PIXELS (1920U * 1080U)

static const char *TAG = "image_rotate";

static int lua_image_rotate_normalize_angle(int angle_degrees)
{
    int angle = angle_degrees % 360;

    if (angle < 0) {
        angle += 360;
    }
    return angle;
}

static esp_err_t lua_image_rotate_alloc(size_t bytes, uint8_t **out)
{
    *out = (uint8_t *)heap_caps_aligned_calloc(16, 1, bytes, MALLOC_CAP_8BIT | MALLOC_CAP_SPIRAM);
    if (*out == NULL) {
        ESP_LOGE(TAG, "rotate output alloc failed: %u bytes", (unsigned)bytes);
        return ESP_ERR_NO_MEM;
    }
    return ESP_OK;
}

static void rotate_pixels(const uint8_t *src,
                          int sw,
                          int sh,
                          uint8_t *dst,
                          int angle,
                          size_t bytes_per_pixel)
{
    int dw = (angle == 90 || angle == 270) ? sh : sw;

    for (int sy = 0; sy < sh; sy++) {
        for (int sx = 0; sx < sw; sx++) {
            int dx = sx;
            int dy = sy;

            switch (angle) {
            case 90:
                dx = sh - 1 - sy;
                dy = sx;
                break;
            case 180:
                dx = sw - 1 - sx;
                dy = sh - 1 - sy;
                break;
            case 270:
                dx = sy;
                dy = sw - 1 - sx;
                break;
            default:
                break;
            }

            memcpy(dst + ((size_t)dy * (size_t)dw + (size_t)dx) * bytes_per_pixel,
                   src + ((size_t)sy * (size_t)sw + (size_t)sx) * bytes_per_pixel,
                   bytes_per_pixel);
        }
    }
}

esp_err_t lua_image_rotate_view(const lua_image_view_t *src,
                                int angle_degrees,
                                lua_image_view_t *out)
{
    int angle;
    int dst_width;
    int dst_height;
    size_t bpp;
    size_t pixel_count;
    size_t output_bytes;
    uint8_t *buffer = NULL;
    esp_err_t err;

    if (src == NULL || out == NULL || src->data == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    memset(out, 0, sizeof(*out));
    if (src->width <= 0 || src->height <= 0) {
        ESP_LOGE(TAG, "invalid rotate dims: %dx%d", src->width, src->height);
        return ESP_ERR_INVALID_SIZE;
    }
    if ((size_t)src->width > LUA_IMAGE_ROTATE_MAX_PIXELS / (size_t)src->height) {
        ESP_LOGE(TAG, "rotate source exceeds pixel limit: %dx%d", src->width, src->height);
        return ESP_ERR_INVALID_SIZE;
    }

    angle = lua_image_rotate_normalize_angle(angle_degrees);
    if (angle != 0 && angle != 90 && angle != 180 && angle != 270) {
        ESP_LOGE(TAG, "unsupported rotate angle: %d", angle_degrees);
        return ESP_ERR_NOT_SUPPORTED;
    }

    switch (src->format) {
    case LUA_IMAGE_FORMAT_GRAY8:
        bpp = 1;
        break;
    case LUA_IMAGE_FORMAT_RGB565LE:
        bpp = 2;
        break;
    default:
        ESP_LOGE(TAG, "rotate only supports GRAY8 / RGB565LE, got %s", lua_image_format_name(src->format));
        return ESP_ERR_NOT_SUPPORTED;
    }

    pixel_count = (size_t)src->width * (size_t)src->height;
    if (src->bytes < pixel_count * bpp) {
        ESP_LOGE(TAG, "rotate source buffer too small: %u < %u", (unsigned)src->bytes, (unsigned)(pixel_count * bpp));
        return ESP_ERR_INVALID_SIZE;
    }

    dst_width = (angle == 90 || angle == 270) ? src->height : src->width;
    dst_height = (angle == 90 || angle == 270) ? src->width : src->height;
    output_bytes = (size_t)dst_width * (size_t)dst_height * bpp;
    err = lua_image_rotate_alloc(output_bytes, &buffer);
    if (err != ESP_OK) {
        return err;
    }

    rotate_pixels(src->data, src->width, src->height, buffer, angle, bpp);

    out->data = buffer;
    out->bytes = output_bytes;
    out->width = dst_width;
    out->height = dst_height;
    out->format = src->format;
    out->owned = true;
    strlcpy(out->source_format, src->source_format, sizeof(out->source_format));
    return ESP_OK;
}
