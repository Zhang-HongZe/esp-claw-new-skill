---
{
  "name": "qintianjian",
  "description": "查询上海或指定地区在今天或指定日期的日出、日落、太阳正午和晨昏蒙影时间；当用户提到日出日落、sunrise、sunset、天亮、天黑时使用。Requires cap_http_request and api.sunrise-sunset.org in the HTTP allowlist.",
  "metadata": {
    "cap_groups": [
      "cap_lua",
      "cap_http_request"
    ],
    "manage_mode": "readonly",
    "tags": [
      "sunrise",
      "sunset",
      "astronomy",
      "timezone",
      "solar"
    ]
  }
}
---

# 钦天监

当用户想查询上海或其他地区今天或指定日期的日出、日落、太阳正午、白昼长度或晨昏蒙影时间时，使用这个技能。

运行且只运行一个绑定 Lua 脚本，并使用 `lua_run_script`：

```json
{"path":"{CUR_SKILL_DIR}/scripts/get_sun_times.lua","args":{"date":"today","formatted":0},"timeout_ms":20000}
```

如果脚本执行报错，直接把错误报告给用户。
除非用户明确要求，否则不要在同一轮里改坐标、改日期、改时区，或切换到别的网络接口重试。

## Prerequisites

- 需要启用 `cap_http_request`。
- HTTP allowlist 里需要包含 `api.sunrise-sunset.org`。
- 默认坐标是上海 `lat=31.2304`、`lng=121.4737`，默认时区是 `Asia/Shanghai`。
- 如果用户要查询其他地区但没有直接给经纬度，先由模型根据地区名补出对应经纬度，再调用脚本。
- 如果用户显式传入 `tzid`，脚本按传入值请求；若不传 `tzid`，脚本默认使用 `Asia/Shanghai`。

## Script Args Schema

```json
{
  "type": "object",
  "properties": {
    "lat": {
      "type": "number",
      "minimum": -90,
      "maximum": 90,
      "default": 31.2304,
      "description": "Optional. Latitude in decimal degrees. Defaults to Shanghai."
    },
    "lng": {
      "type": "number",
      "minimum": -180,
      "maximum": 180,
      "default": 121.4737,
      "description": "Optional. Longitude in decimal degrees. Defaults to Shanghai."
    },
    "date": {
      "type": "string",
      "description": "Optional. Prefer YYYY-MM-DD, or use today/tomorrow/yesterday. Defaults to today."
    },
    "tzid": {
      "type": "string",
      "default": "Asia/Shanghai",
      "description": "Optional. IANA timezone such as Asia/Shanghai. Defaults to Asia/Shanghai."
    },
    "formatted": {
      "type": "integer",
      "enum": [0, 1],
      "default": 0,
      "description": "Optional. 0 returns ISO 8601 timestamps and numeric day_length seconds. 1 returns human-formatted strings such as 7:27:02 AM."
    }
  }
}
```

## Tool Call Inputs

默认查询上海今天的日出日落：

```json
{"path":"{CUR_SKILL_DIR}/scripts/get_sun_times.lua","args":{"date":"today","formatted":0},"timeout_ms":20000}
```

查询北京今天的日出日落，并返回北京时间：

```json
{"path":"{CUR_SKILL_DIR}/scripts/get_sun_times.lua","args":{"lat":39.9042,"lng":116.4074,"tzid":"Asia/Shanghai","date":"today","formatted":0},"timeout_ms":20000}
```

查询纽约某一天的日出日落：

```json
{"path":"{CUR_SKILL_DIR}/scripts/get_sun_times.lua","args":{"lat":40.7128,"lng":-74.0060,"tzid":"America/New_York","date":"2026-06-24","formatted":0},"timeout_ms":20000}
```

## Behavior

- 脚本访问官方接口 `https://api.sunrise-sunset.org/json`。
- 参数名与官方 API 对齐，使用 `lat`、`lng`、`date`、`formatted`、`tzid`。
- 未传 `lat`、`lng` 时默认查询上海；未传 `tzid` 时默认使用 `Asia/Shanghai`。
- `formatted` 默认使用 `0`，这样返回值会带 ISO 8601 时间和时区偏移，更适合直接报告。
- 成功时脚本打印一个 JSON 对象，包含请求参数、接口状态、实际时区、日出日落结果以及简短中文摘要。
- 当接口返回 `INVALID_TZID` 时，脚本不会丢弃结果，而是保留返回值并明确说明结果已经回退为 UTC。
- 如果 HTTP 请求失败、allowlist 拒绝、JSON 解析失败，或接口返回 `INVALID_REQUEST`、`INVALID_DATE`、`UNKNOWN_ERROR` 等状态，直接报告错误。

## Recommended Flow

1. 如果用户没有指定地区，默认查询上海。
2. 如果用户指定了地区名但没给经纬度，先由模型补出该地区对应的 `lat` 和 `lng`，再调用脚本；如果地区含义明显歧义，再向用户确认。
3. 选择 `date`。查询当前日出日落时优先用 `today`，查询指定日期时优先用 `YYYY-MM-DD`。
4. 除非用户明确要接口原始文本时间格式，否则优先使用 `formatted: 0`。
5. 使用 `lua_run_script` 运行 `{CUR_SKILL_DIR}/scripts/get_sun_times.lua`，`timeout_ms` 设为 `20000`。
6. 向用户清楚报告日出、日落和实际返回时区；如果接口回退到了 UTC，也要明确说明。
