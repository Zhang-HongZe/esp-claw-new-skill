/*
 * SPDX-FileCopyrightText: 2026 Espressif Systems (Shanghai) CO LTD
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"
#include "lua_image_convert.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Crop an already-decoded image view.
 *
 * Only RGB565LE and GRAY8 source formats are supported, and the output format
 * matches the source format. @p src_x / @p src_y are zero-based source pixels.
 * When @p flip_y is true, the cropped output is vertically flipped while it is
 * copied.
 *
 * On ESP_OK, @p out owns its own buffer (out->owned == true) and must be
 * released with lua_image_release_view().
 */
esp_err_t lua_image_crop_view(const lua_image_view_t *src,
                              int src_x,
                              int src_y,
                              int crop_width,
                              int crop_height,
                              bool flip_y,
                              lua_image_view_t *out);

#ifdef __cplusplus
}
#endif
