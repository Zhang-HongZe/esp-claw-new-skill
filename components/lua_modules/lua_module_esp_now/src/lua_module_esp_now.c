/*
 * SPDX-FileCopyrightText: 2026 Espressif Systems (Shanghai) CO LTD
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include "lua_module_esp_now.h"

#include <ctype.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cap_lua.h"
#include "esp_err.h"
#include "esp_idf_version.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_now.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "lauxlib.h"

#define LUA_MODULE_ESPNOW_NAME "esp_now"

#define LUA_ESPNOW_EVENT_QUEUE_LEN 32
#define LUA_ESPNOW_PROCESS_EVENTS_MAX 8
#define LUA_ESPNOW_MAC_STR_LEN 17
#define LUA_ESPNOW_PMK_LEN 16
#define LUA_ESPNOW_LMK_LEN 16

#ifdef ESP_NOW_MAX_DATA_LEN
#define LUA_ESPNOW_DATA_MAX ESP_NOW_MAX_DATA_LEN
#else
#define LUA_ESPNOW_DATA_MAX 250
#endif

typedef enum {
    LUA_ESPNOW_EVENT_RECV,
    LUA_ESPNOW_EVENT_SEND_COMPLETE,
} lua_espnow_event_type_t;

typedef struct {
    lua_espnow_event_type_t type;
    uint8_t mac[ESP_NOW_ETH_ALEN];
    uint8_t *data;
    size_t data_len;
    esp_now_send_status_t send_status;
    int rssi;
    uint8_t channel;
    bool has_rssi;
    bool has_channel;
} lua_espnow_event_t;

typedef struct {
    QueueHandle_t event_queue;
    int event_callback_ref;
    bool initialized;
    volatile uint32_t event_dropped;
} lua_espnow_runtime_t;

static const char *TAG = "lua_esp_now";

static lua_espnow_runtime_t s_espnow_rt = {
    .event_callback_ref = LUA_NOREF,
};

static int lua_espnow_push_runtime_error(lua_State *L, esp_err_t err)
{
    lua_pushnil(L);
    lua_pushstring(L, esp_err_to_name(err));
    return 2;
}

static int lua_espnow_push_error(lua_State *L, const char *err)
{
    lua_pushnil(L);
    lua_pushstring(L, err);
    return 2;
}

static int lua_espnow_hex_nibble(char c)
{
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    c = (char)tolower((unsigned char)c);
    if (c >= 'a' && c <= 'f') {
        return c - 'a' + 10;
    }
    return -1;
}

static bool lua_espnow_parse_mac_bytes(const char *value, size_t len, uint8_t out[ESP_NOW_ETH_ALEN])
{
    if (len == ESP_NOW_ETH_ALEN) {
        memcpy(out, value, ESP_NOW_ETH_ALEN);
        return true;
    }

    if (len != LUA_ESPNOW_MAC_STR_LEN) {
        return false;
    }

    for (size_t i = 0; i < ESP_NOW_ETH_ALEN; i++) {
        int hi = lua_espnow_hex_nibble(value[i * 3]);
        int lo = lua_espnow_hex_nibble(value[i * 3 + 1]);

        if (hi < 0 || lo < 0) {
            return false;
        }
        if (i < ESP_NOW_ETH_ALEN - 1 && value[i * 3 + 2] != ':') {
            return false;
        }
        out[i] = (uint8_t)((hi << 4) | lo);
    }
    return true;
}

static void lua_espnow_check_mac(lua_State *L, int index, uint8_t out[ESP_NOW_ETH_ALEN])
{
    size_t len = 0;
    const char *value = luaL_checklstring(L, index, &len);

    if (!lua_espnow_parse_mac_bytes(value, len, out)) {
        luaL_error(L, "esp_now mac must be 'aa:bb:cc:dd:ee:ff' or a 6-byte string");
    }
}

static void lua_espnow_get_mac_field(lua_State *L, int table_index,
                                     const char *field_name,
                                     uint8_t out[ESP_NOW_ETH_ALEN])
{
    table_index = lua_absindex(L, table_index);
    lua_getfield(L, table_index, field_name);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        luaL_error(L, "missing required field '%s'", field_name);
    }
    lua_espnow_check_mac(L, -1, out);
    lua_pop(L, 1);
}

static void lua_espnow_push_mac(lua_State *L, const uint8_t mac[ESP_NOW_ETH_ALEN])
{
    char buf[LUA_ESPNOW_MAC_STR_LEN + 1];

    snprintf(buf,
             sizeof(buf),
             "%02x:%02x:%02x:%02x:%02x:%02x",
             mac[0],
             mac[1],
             mac[2],
             mac[3],
             mac[4],
             mac[5]);
    lua_pushstring(L, buf);
}

static bool lua_espnow_get_bool_field(lua_State *L, int table_index,
                                      const char *field_name, bool default_value)
{
    bool value = default_value;

    table_index = lua_absindex(L, table_index);
    lua_getfield(L, table_index, field_name);
    if (!lua_isnil(L, -1)) {
        if (!lua_isboolean(L, -1)) {
            lua_pop(L, 1);
            luaL_error(L, "field '%s' must be a boolean", field_name);
        }
        value = lua_toboolean(L, -1);
    }
    lua_pop(L, 1);
    return value;
}

static int lua_espnow_get_int_field(lua_State *L, int table_index,
                                    const char *field_name, int default_value,
                                    int min_value, int max_value)
{
    int value = default_value;

    table_index = lua_absindex(L, table_index);
    lua_getfield(L, table_index, field_name);
    if (!lua_isnil(L, -1)) {
        lua_Integer raw = luaL_checkinteger(L, -1);

        if (raw < min_value || raw > max_value) {
            lua_pop(L, 1);
            luaL_error(L, "field '%s' must be %d..%d", field_name, min_value, max_value);
        }
        value = (int)raw;
    }
    lua_pop(L, 1);
    return value;
}

static wifi_interface_t lua_espnow_get_ifidx_field(lua_State *L, int table_index)
{
    wifi_interface_t ifidx = WIFI_IF_STA;

    table_index = lua_absindex(L, table_index);
    lua_getfield(L, table_index, "ifidx");
    if (!lua_isnil(L, -1)) {
        const char *value = luaL_checkstring(L, -1);

        if (strcmp(value, "sta") == 0) {
            ifidx = WIFI_IF_STA;
        } else if (strcmp(value, "ap") == 0) {
            ifidx = WIFI_IF_AP;
        } else {
            lua_pop(L, 1);
            luaL_error(L, "field 'ifidx' must be 'sta' or 'ap'");
        }
    }
    lua_pop(L, 1);
    return ifidx;
}

static bool lua_espnow_get_key_field(lua_State *L, int table_index,
                                     const char *field_name,
                                     uint8_t *out, size_t expected_len)
{
    bool has_value = false;

    table_index = lua_absindex(L, table_index);
    lua_getfield(L, table_index, field_name);
    if (!lua_isnil(L, -1)) {
        size_t len = 0;
        const char *value = luaL_checklstring(L, -1, &len);

        if (len != expected_len) {
            lua_pop(L, 1);
            luaL_error(L, "field '%s' must be %u bytes", field_name, (unsigned)expected_len);
        }
        memcpy(out, value, expected_len);
        has_value = true;
    }
    lua_pop(L, 1);
    return has_value;
}

static esp_err_t lua_espnow_runtime_ensure(void)
{
    if (!s_espnow_rt.event_queue) {
        s_espnow_rt.event_queue = xQueueCreate(LUA_ESPNOW_EVENT_QUEUE_LEN,
                                               sizeof(lua_espnow_event_t *));
        if (!s_espnow_rt.event_queue) {
            return ESP_ERR_NO_MEM;
        }
    }
    return ESP_OK;
}

static void lua_espnow_event_free(lua_espnow_event_t *event)
{
    if (!event) {
        return;
    }
    free(event->data);
    free(event);
}

static void lua_espnow_events_clear(void)
{
    lua_espnow_event_t *event = NULL;

    if (!s_espnow_rt.event_queue) {
        return;
    }
    while (xQueueReceive(s_espnow_rt.event_queue, &event, 0) == pdTRUE) {
        lua_espnow_event_free(event);
    }
}

static void lua_espnow_event_enqueue(lua_espnow_event_t *event)
{
    if (!event) {
        return;
    }
    if (!s_espnow_rt.event_queue ||
            xQueueSend(s_espnow_rt.event_queue, &event, 0) != pdTRUE) {
        __atomic_add_fetch(&s_espnow_rt.event_dropped, 1, __ATOMIC_RELAXED);
        lua_espnow_event_free(event);
    }
}

static lua_espnow_event_t *lua_espnow_event_alloc(lua_espnow_event_type_t type,
                                                  const uint8_t *mac)
{
    lua_espnow_event_t *event = calloc(1, sizeof(*event));

    if (!event) {
        __atomic_add_fetch(&s_espnow_rt.event_dropped, 1, __ATOMIC_RELAXED);
        return NULL;
    }
    event->type = type;
    if (mac) {
        memcpy(event->mac, mac, ESP_NOW_ETH_ALEN);
    }
    return event;
}

#if ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(5, 0, 0)
static void lua_espnow_send_cb(const esp_now_send_info_t *tx_info, esp_now_send_status_t status)
{
    const uint8_t *mac_addr = (tx_info && tx_info->des_addr) ? tx_info->des_addr : NULL;
#else
static void lua_espnow_send_cb(const uint8_t *mac_addr, esp_now_send_status_t status)
{
#endif
    lua_espnow_event_t *event = NULL;

    if (!mac_addr) {
        return;
    }
    event = lua_espnow_event_alloc(LUA_ESPNOW_EVENT_SEND_COMPLETE, mac_addr);
    if (!event) {
        return;
    }
    event->send_status = status;
    lua_espnow_event_enqueue(event);
}

#if ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(5, 0, 0)
static void lua_espnow_recv_cb(const esp_now_recv_info_t *info, const uint8_t *data, int data_len)
{
    const uint8_t *mac_addr = info ? info->src_addr : NULL;
#else
static void lua_espnow_recv_cb(const uint8_t *mac_addr, const uint8_t *data, int data_len)
{
#endif
    lua_espnow_event_t *event = NULL;

    if (!mac_addr || data_len < 0 || (data_len > 0 && !data)) {
        return;
    }

    event = lua_espnow_event_alloc(LUA_ESPNOW_EVENT_RECV, mac_addr);
    if (!event) {
        return;
    }
    if (data_len > 0) {
        event->data = malloc((size_t)data_len);
        if (!event->data) {
            __atomic_add_fetch(&s_espnow_rt.event_dropped, 1, __ATOMIC_RELAXED);
            lua_espnow_event_free(event);
            return;
        }
        memcpy(event->data, data, (size_t)data_len);
        event->data_len = (size_t)data_len;
    }
#if ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(5, 0, 0)
    if (info && info->rx_ctrl) {
        event->rssi = info->rx_ctrl->rssi;
        event->channel = info->rx_ctrl->channel;
        event->has_rssi = true;
        event->has_channel = true;
    }
#endif
    lua_espnow_event_enqueue(event);
}

static int lua_espnow_init(lua_State *L)
{
    uint8_t pmk[LUA_ESPNOW_PMK_LEN] = {0};
    bool has_pmk = false;
    esp_err_t err;

    err = lua_espnow_runtime_ensure();
    if (err != ESP_OK) {
        return lua_espnow_push_runtime_error(L, err);
    }

    if (!lua_isnoneornil(L, 1)) {
        luaL_checktype(L, 1, LUA_TTABLE);
        has_pmk = lua_espnow_get_key_field(L, 1, "pmk", pmk, sizeof(pmk));
    }

    if (s_espnow_rt.initialized) {
        lua_pushboolean(L, 1);
        return 1;
    }

    err = esp_now_init();
    if (err != ESP_OK) {
        return lua_espnow_push_runtime_error(L, err);
    }

    err = esp_now_register_send_cb(lua_espnow_send_cb);
    if (err != ESP_OK) {
        esp_now_deinit();
        return lua_espnow_push_runtime_error(L, err);
    }

    err = esp_now_register_recv_cb(lua_espnow_recv_cb);
    if (err != ESP_OK) {
        esp_now_unregister_send_cb();
        esp_now_deinit();
        return lua_espnow_push_runtime_error(L, err);
    }

    if (has_pmk) {
        err = esp_now_set_pmk(pmk);
        if (err != ESP_OK) {
            esp_now_unregister_recv_cb();
            esp_now_unregister_send_cb();
            esp_now_deinit();
            return lua_espnow_push_runtime_error(L, err);
        }
    }

    s_espnow_rt.initialized = true;
    lua_pushboolean(L, 1);
    return 1;
}

static int lua_espnow_deinit(lua_State *L)
{
    esp_err_t err;

    if (!s_espnow_rt.initialized) {
        lua_espnow_events_clear();
        lua_pushboolean(L, 1);
        return 1;
    }

    esp_now_unregister_recv_cb();
    esp_now_unregister_send_cb();
    err = esp_now_deinit();
    if (err != ESP_OK) {
        return lua_espnow_push_runtime_error(L, err);
    }

    s_espnow_rt.initialized = false;
    lua_espnow_events_clear();
    lua_pushboolean(L, 1);
    return 1;
}

static int lua_espnow_add_peer(lua_State *L)
{
    esp_now_peer_info_t peer = {0};
    bool encrypt = false;
    bool has_lmk = false;
    esp_err_t err;

    if (!s_espnow_rt.initialized) {
        return lua_espnow_push_error(L, "esp_now_not_initialized");
    }

    luaL_checktype(L, 1, LUA_TTABLE);
    lua_espnow_get_mac_field(L, 1, "mac", peer.peer_addr);
    peer.channel = (uint8_t)lua_espnow_get_int_field(L, 1, "channel", 0, 0, 14);
    peer.ifidx = lua_espnow_get_ifidx_field(L, 1);
    encrypt = lua_espnow_get_bool_field(L, 1, "encrypt", false);
    peer.encrypt = encrypt;
    has_lmk = lua_espnow_get_key_field(L, 1, "lmk", peer.lmk, LUA_ESPNOW_LMK_LEN);
    if (encrypt && !has_lmk) {
        return luaL_error(L, "field 'lmk' is required when encrypt=true");
    }

    if (esp_now_is_peer_exist(peer.peer_addr)) {
        err = esp_now_mod_peer(&peer);
    } else {
        err = esp_now_add_peer(&peer);
    }
    if (err != ESP_OK) {
        return lua_espnow_push_runtime_error(L, err);
    }

    lua_pushboolean(L, 1);
    return 1;
}

static int lua_espnow_del_peer(lua_State *L)
{
    uint8_t mac[ESP_NOW_ETH_ALEN];
    esp_err_t err;

    if (!s_espnow_rt.initialized) {
        return lua_espnow_push_error(L, "esp_now_not_initialized");
    }

    lua_espnow_check_mac(L, 1, mac);
    err = esp_now_del_peer(mac);
    if (err != ESP_OK) {
        return lua_espnow_push_runtime_error(L, err);
    }

    lua_pushboolean(L, 1);
    return 1;
}

static int lua_espnow_has_peer(lua_State *L)
{
    uint8_t mac[ESP_NOW_ETH_ALEN];

    if (!s_espnow_rt.initialized) {
        lua_pushboolean(L, 0);
        return 1;
    }

    lua_espnow_check_mac(L, 1, mac);
    lua_pushboolean(L, esp_now_is_peer_exist(mac));
    return 1;
}

static int lua_espnow_send(lua_State *L)
{
    uint8_t mac[ESP_NOW_ETH_ALEN];
    size_t data_len = 0;
    const char *data = NULL;
    esp_err_t err;

    if (!s_espnow_rt.initialized) {
        return lua_espnow_push_error(L, "esp_now_not_initialized");
    }

    luaL_checktype(L, 1, LUA_TTABLE);
    lua_espnow_get_mac_field(L, 1, "mac", mac);
    lua_getfield(L, 1, "data");
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        luaL_error(L, "missing required field 'data'");
    }
    data = luaL_checklstring(L, -1, &data_len);
    if (data_len > LUA_ESPNOW_DATA_MAX) {
        lua_pop(L, 1);
        return luaL_error(L, "field 'data' must be <= %d bytes", LUA_ESPNOW_DATA_MAX);
    }
    err = esp_now_send(mac, (const uint8_t *)data, data_len);
    lua_pop(L, 1);
    if (err != ESP_OK) {
        return lua_espnow_push_runtime_error(L, err);
    }

    lua_pushboolean(L, 1);
    return 1;
}

static void lua_espnow_push_event(lua_State *L, const lua_espnow_event_t *event)
{
    lua_newtable(L);
    switch (event->type) {
    case LUA_ESPNOW_EVENT_RECV:
        lua_pushstring(L, "recv");
        lua_setfield(L, -2, "type");
        lua_espnow_push_mac(L, event->mac);
        lua_setfield(L, -2, "mac");
        lua_pushlstring(L, (const char *)event->data, event->data_len);
        lua_setfield(L, -2, "data");
        if (event->has_rssi) {
            lua_pushinteger(L, event->rssi);
            lua_setfield(L, -2, "rssi");
        }
        if (event->has_channel) {
            lua_pushinteger(L, event->channel);
            lua_setfield(L, -2, "channel");
        }
        break;
    case LUA_ESPNOW_EVENT_SEND_COMPLETE:
        lua_pushstring(L, "send_complete");
        lua_setfield(L, -2, "type");
        lua_espnow_push_mac(L, event->mac);
        lua_setfield(L, -2, "mac");
        lua_pushstring(L, event->send_status == ESP_NOW_SEND_SUCCESS ? "ok" : "fail");
        lua_setfield(L, -2, "status");
        break;
    }
}

static bool lua_espnow_push_callback(lua_State *L)
{
    int callback_ref = s_espnow_rt.event_callback_ref;

    if (callback_ref == LUA_NOREF) {
        return false;
    }
    lua_rawgeti(L, LUA_REGISTRYINDEX, callback_ref);
    if (!lua_isfunction(L, -1)) {
        lua_pop(L, 1);
        luaL_unref(L, LUA_REGISTRYINDEX, callback_ref);
        if (s_espnow_rt.event_callback_ref == callback_ref) {
            s_espnow_rt.event_callback_ref = LUA_NOREF;
        }
        lua_espnow_events_clear();
        return false;
    }
    return true;
}

static int lua_espnow_on_event(lua_State *L)
{
    if (lua_isnil(L, 1)) {
        if (s_espnow_rt.event_callback_ref != LUA_NOREF) {
            luaL_unref(L, LUA_REGISTRYINDEX, s_espnow_rt.event_callback_ref);
            s_espnow_rt.event_callback_ref = LUA_NOREF;
        }
        lua_espnow_events_clear();
        lua_pushboolean(L, 1);
        return 1;
    }

    luaL_checktype(L, 1, LUA_TFUNCTION);
    lua_pushvalue(L, 1);
    if (s_espnow_rt.event_callback_ref != LUA_NOREF) {
        luaL_unref(L, LUA_REGISTRYINDEX, s_espnow_rt.event_callback_ref);
    }
    s_espnow_rt.event_callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    lua_espnow_events_clear();
    lua_pushboolean(L, 1);
    return 1;
}

static int lua_espnow_process_events(lua_State *L)
{
    int timeout_ms = lua_isnoneornil(L, 1) ? 0 : (int)luaL_checkinteger(L, 1);
    TickType_t first_wait;
    int processed = 0;

    if (timeout_ms < 0) {
        timeout_ms = 0;
    }
    if (!s_espnow_rt.event_queue || s_espnow_rt.event_callback_ref == LUA_NOREF) {
        lua_pushinteger(L, 0);
        return 1;
    }

    first_wait = timeout_ms > 0 ? pdMS_TO_TICKS(timeout_ms) : 0;
    while (processed < LUA_ESPNOW_PROCESS_EVENTS_MAX) {
        TickType_t wait = processed == 0 ? first_wait : 0;
        lua_espnow_event_t *event = NULL;

        if (cap_lua_runtime_stop_requested(L)) {
            return luaL_error(L, "stop requested");
        }
        if (xQueueReceive(s_espnow_rt.event_queue, &event, wait) != pdTRUE) {
            break;
        }
        if (!lua_espnow_push_callback(L)) {
            lua_espnow_event_free(event);
            break;
        }
        lua_espnow_push_event(L, event);
        lua_espnow_event_free(event);
        if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
            const char *msg = lua_tostring(L, -1);

            ESP_LOGE(TAG, "ESP-NOW event callback error: %s", msg ? msg : "(nil)");
            return lua_error(L);
        }
        processed++;
    }

    lua_pushinteger(L, processed);
    return 1;
}

static int lua_espnow_stats(lua_State *L)
{
    lua_newtable(L);
    lua_pushboolean(L, s_espnow_rt.initialized);
    lua_setfield(L, -2, "initialized");
    lua_pushinteger(L, __atomic_load_n(&s_espnow_rt.event_dropped, __ATOMIC_RELAXED));
    lua_setfield(L, -2, "event_dropped");
    lua_pushinteger(L, LUA_ESPNOW_EVENT_QUEUE_LEN);
    lua_setfield(L, -2, "event_queue_capacity");
    lua_pushinteger(L, s_espnow_rt.event_queue ? uxQueueMessagesWaiting(s_espnow_rt.event_queue) : 0);
    lua_setfield(L, -2, "event_queue_depth");
    lua_pushinteger(L, LUA_ESPNOW_DATA_MAX);
    lua_setfield(L, -2, "max_data_len");

    if (s_espnow_rt.initialized) {
        uint32_t version = 0;
        esp_now_peer_num_t peer_num = {0};

        if (esp_now_get_version(&version) == ESP_OK) {
            lua_pushinteger(L, version);
            lua_setfield(L, -2, "version");
        }
        if (esp_now_get_peer_num(&peer_num) == ESP_OK) {
            lua_pushinteger(L, peer_num.total_num);
            lua_setfield(L, -2, "peer_total");
            lua_pushinteger(L, peer_num.encrypt_num);
            lua_setfield(L, -2, "peer_encrypted");
        }
    }
    return 1;
}

static int lua_espnow_get_mac(lua_State *L)
{
    const char *which = luaL_optstring(L, 1, "sta");
    uint8_t mac[ESP_NOW_ETH_ALEN];
    esp_err_t err;

    if (strcmp(which, "sta") == 0) {
        err = esp_read_mac(mac, ESP_MAC_WIFI_STA);
    } else if (strcmp(which, "ap") == 0) {
        err = esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP);
    } else {
        return luaL_error(L, "esp_now.get_mac argument must be 'sta' or 'ap'");
    }

    if (err != ESP_OK) {
        return lua_espnow_push_runtime_error(L, err);
    }
    lua_espnow_push_mac(L, mac);
    return 1;
}

int luaopen_esp_now(lua_State *L)
{
    static const luaL_Reg funcs[] = {
        {"init", lua_espnow_init},
        {"deinit", lua_espnow_deinit},
        {"add_peer", lua_espnow_add_peer},
        {"del_peer", lua_espnow_del_peer},
        {"has_peer", lua_espnow_has_peer},
        {"send", lua_espnow_send},
        {"on_event", lua_espnow_on_event},
        {"process_events", lua_espnow_process_events},
        {"stats", lua_espnow_stats},
        {"get_mac", lua_espnow_get_mac},
        {NULL, NULL},
    };

    lua_newtable(L);
    luaL_setfuncs(L, funcs, 0);
    return 1;
}

esp_err_t lua_module_esp_now_register(void)
{
    return cap_lua_register_module(LUA_MODULE_ESPNOW_NAME, luaopen_esp_now);
}
