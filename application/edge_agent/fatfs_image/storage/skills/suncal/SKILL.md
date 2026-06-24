---
{
  "name": "suncal",
  "description": "本地计算指定经纬度在今天或指定日期的日出、日落、月升、月落、太阳正午、晨昏蒙影和月相信息；当用户提到 sunrise、sunset、moonrise、moonset、月升月落时使用。不调用 API。",
  "metadata": {
    "cap_groups": [
      "cap_lua"
    ],
    "manage_mode": "readonly",
    "tags": [
      "sunrise",
      "sunset",
      "moonrise",
      "moonset",
      "astronomy",
      "local-compute"
    ]
  }
}
---

# SunCal

当用户想查询某个地点今天或指定日期的日出、日落、月升、月落、太阳正午、晨昏蒙影、白昼长度或月相时，使用这个技能。

运行且只运行一个绑定 Lua 脚本，并使用 `lua_run_script`：

```json
{"path":"{CUR_SKILL_DIR}/scripts/get_sun_moon_info.lua","args":{"lat":39.9042,"lng":116.4074,"date":"today","utc_offset_minutes":480},"timeout_ms":10000}
```

如果脚本执行报错，直接把错误报告给用户。
除非用户明确要求，否则不要在同一轮里改坐标、改日期、改时区偏移量，或切换到别的实现重试。

## Local Compute Only

- 这个 skill 基于本地数学模型计算，不调用任何 HTTP API 或外部网络服务。
- 结果由设备本地 Lua 脚本直接计算得出，适合离线环境。

## Script Args Schema

```json
{
  "type": "object",
  "properties": {
    "lat": {
      "type": "number",
      "minimum": -90,
      "maximum": 90,
      "description": "Required. Latitude in decimal degrees."
    },
    "lng": {
      "type": "number",
      "minimum": -180,
      "maximum": 180,
      "description": "Required. Longitude in decimal degrees."
    },
    "date": {
      "type": "string",
      "description": "Optional. Prefer YYYY-MM-DD, or use today/tomorrow/yesterday. Defaults to today."
    },
    "utc_offset_minutes": {
      "type": "integer",
      "description": "Optional. Local civil-day and output offset in minutes, for example 480 for UTC+08:00 and -240 for UTC-04:00. If omitted, the script uses the device's current local timezone."
    },
    "height_m": {
      "type": "number",
      "minimum": 0,
      "default": 0,
      "description": "Optional. Observer height above the horizon in meters. Used for sunrise/sunset calculations."
    }
  },
  "required": ["lat", "lng"]
}
```

## Tool Call Inputs

查询北京今天的日出日落和月升月落，并按 UTC+08:00 输出本地时间：

```json
{"path":"{CUR_SKILL_DIR}/scripts/get_sun_moon_info.lua","args":{"lat":39.9042,"lng":116.4074,"date":"today","utc_offset_minutes":480},"timeout_ms":10000}
```

查询纽约某一天的日升月落信息，并按 UTC-04:00 作为当地日历日和输出偏移：

```json
{"path":"{CUR_SKILL_DIR}/scripts/get_sun_moon_info.lua","args":{"lat":40.7128,"lng":-74.0060,"date":"2026-06-24","utc_offset_minutes":-240},"timeout_ms":10000}
```

如果用户没有给出 `utc_offset_minutes`，则使用设备当前本地时区来确定“today/tomorrow/yesterday”和本地时间输出：

```json
{"path":"{CUR_SKILL_DIR}/scripts/get_sun_moon_info.lua","args":{"lat":51.5072,"lng":-0.1276,"date":"today"},"timeout_ms":10000}
```

## Behavior

- 脚本在本地计算太阳时刻，包括 `sunrise`、`sunset`、`solarNoon`、`dawn`、`dusk`、`nauticalDawn`、`nauticalDusk`、`nightEnd`、`night`、`goldenHourEnd`、`goldenHour`。
- 脚本在本地计算月升月落，并返回月相照明比例、相位值和中文相位名称。
- 当提供 `utc_offset_minutes` 时，脚本把该偏移量同时用于：
  - 解释所选 `date` 是哪个当地日历日；
  - 按该偏移量格式化返回的本地时间。
- 当未提供 `utc_offset_minutes` 时：
  - `today/tomorrow/yesterday` 按设备当前本地时区解释；
  - 输出里仍会同时返回 UTC 时间；
  - `local_iso` 字段按设备当前本地时区格式化。
- 高纬地区可能出现某一天没有日出、没有日落、没有月升或没有月落；脚本会返回 `exists: false` 以及对应的 `alwaysUp` 或 `alwaysDown` 标记。

## Recommended Flow

1. 不要猜测坐标，优先使用用户明确提供的 `lat` 和 `lng`。
2. 如果用户问“今天/明天/昨天”，优先使用 `today`、`tomorrow`、`yesterday`。
3. 如果用户关心某地“当地钟表时间”，优先传入该地 `utc_offset_minutes`。
4. 使用 `lua_run_script` 运行 `{CUR_SKILL_DIR}/scripts/get_sun_moon_info.lua`，`timeout_ms` 设为 `10000`。
5. 成功后优先向用户报告日出、日落、月升、月落，以及结果采用的时间基准。
6. 如果脚本报错，直接报告错误，不要擅自改参数重试。

## Acknowledgements

本 skill 的计算方式参考并致谢本地仓库 `/home/zhanghongze/suncalc` 中的 SunCalc 实现。
这里采用的是本地计算方案，不调用 API，不依赖外部在线服务。
