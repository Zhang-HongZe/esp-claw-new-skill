/*
 * SPDX-FileCopyrightText: 2026 Espressif Systems (Shanghai) CO LTD
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include "lua_image_crop.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "esp_heap_caps.h"
#include "esp_log.h"

#define LUA_IMAGE_CROP_MAX_PIXELS (1920U * 1080U)

static const char *TAG = "image_crop";

static esp_err_t lua_image_crop_alloc(size_t bytes, uint8_t **out)
{
    *out = (uint8_t *)heap_caps_aligned_calloc(16, 1, bytes, MALLOC_CAP_8BIT | MALLOC_CAP_SPIRAM);
    if (*out == NULL) {
        ESP_LOGE(TAG, "crop output alloc failed: %u bytes", (unsigned)bytes);
        return ESP_ERR_NO_MEM;
    }
    return ESP_OK;
}

static void crop_pixels(const uint8_t *src,
                        int src_width,
                        int src_x,
                        int src_y,
                        int crop_width,
                        int crop_height,
                        bool flip_y,
                        uint8_t *dst,
                        size_t bytes_per_pixel)
{
    size_t row_bytes = (size_t)crop_width * bytes_per_pixel;

    for (int row = 0; row < crop_height; row++) {
        int crop_row = flip_y ? (crop_height - 1 - row) : row;
        const uint8_t *src_row = src + (((size_t)(src_y + crop_row) * (size_t)src_width + (size_t)src_x) *
                                        bytes_per_pixel);
        uint8_t *dst_row = dst + ((size_t)row * row_bytes);
        memcpy(dst_row, src_row, row_bytes);
    }
}

esp_err_t lua_image_crop_view(const lua_image_view_t *src,
                              int src_x,
                              int src_y,
                              int crop_width,
                              int crop_height,
                              bool flip_y,
                              lua_image_view_t *out)
{
    size_t bpp;
    size_t source_pixel_count;
    size_t output_pixel_count;
    size_t output_bytes;
    uint8_t *buffer = NULL;
    esp_err_t err;

    if (src == NULL || out == NULL || src->data == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    memset(out, 0, sizeof(*out));
    if (src->width <= 0 || src->height <= 0 || crop_width <= 0 || crop_height <= 0) {
        ESP_LOGE(TAG, "invalid crop dims: src=%dx%d crop=%dx%d", src->width, src->height, crop_width, crop_height);
        return ESP_ERR_INVALID_SIZE;
    }
    if (src_x < 0 || src_y < 0 || src_x > src->width - crop_width || src_y > src->height - crop_height) {
        ESP_LOGE(TAG, "crop source rect out of bounds: src=%dx%d rect=(%d,%d %dx%d)",
                 src->width, src->height, src_x, src_y, crop_width, crop_height);
        return ESP_ERR_INVALID_SIZE;
    }
    if ((size_t)src->width > LUA_IMAGE_CROP_MAX_PIXELS / (size_t)src->height ||
        (size_t)crop_width > LUA_IMAGE_CROP_MAX_PIXELS / (size_t)crop_height) {
        ESP_LOGE(TAG, "crop exceeds pixel limit: src=%dx%d crop=%dx%d",
                 src->width, src->height, crop_width, crop_height);
        return ESP_ERR_INVALID_SIZE;
    }

    switch (src->format) {
    case LUA_IMAGE_FORMAT_GRAY8:
        bpp = 1;
        break;
    case LUA_IMAGE_FORMAT_RGB565LE:
        bpp = 2;
        break;
    default:
        ESP_LOGE(TAG, "crop only supports GRAY8 / RGB565LE, got %s", lua_image_format_name(src->format));
        return ESP_ERR_NOT_SUPPORTED;
    }

    source_pixel_count = (size_t)src->width * (size_t)src->height;
    if (src->bytes < source_pixel_count * bpp) {
        ESP_LOGE(TAG, "crop source buffer too small: %u < %u", (unsigned)src->bytes,
                 (unsigned)(source_pixel_count * bpp));
        return ESP_ERR_INVALID_SIZE;
    }

    output_pixel_count = (size_t)crop_width * (size_t)crop_height;
    output_bytes = output_pixel_count * bpp;
    err = lua_image_crop_alloc(output_bytes, &buffer);
    if (err != ESP_OK) {
        return err;
    }

    crop_pixels(src->data, src->width, src_x, src_y, crop_width, crop_height, flip_y, buffer, bpp);

    out->data = buffer;
    out->bytes = output_bytes;
    out->width = crop_width;
    out->height = crop_height;
    out->format = src->format;
    out->owned = true;
    strlcpy(out->source_format, src->source_format, sizeof(out->source_format));
    return ESP_OK;
}
