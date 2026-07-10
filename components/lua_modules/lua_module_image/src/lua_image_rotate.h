/*
 * SPDX-FileCopyrightText: 2026 Espressif Systems (Shanghai) CO LTD
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <stdint.h>

#include "esp_err.h"
#include "lua_image_convert.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Rotate an already-decoded image view by a right-angle step.
 *
 * Only RGB565LE and GRAY8 source formats are supported, and the output format
 * matches the source format. @p angle_degrees is clockwise and must be
 * equivalent to 0, 90, 180, or 270 degrees.
 *
 * On ESP_OK, @p out owns its own buffer (out->owned == true) and must be
 * released with lua_image_release_view().
 */
esp_err_t lua_image_rotate_view(const lua_image_view_t *src,
                                int angle_degrees,
                                lua_image_view_t *out);

#ifdef __cplusplus
}
#endif
