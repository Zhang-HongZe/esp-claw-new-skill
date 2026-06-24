local capability = require("capability")
local json = require("json")

local SKILL_ID = "qintianjian"
local API_URL = "https://api.sunrise-sunset.org/json"
local HTTP_TIMEOUT_MS = 20000
local HTTP_MAX_BODY_BYTES = 8192
local DEFAULT_LAT = 31.2304
local DEFAULT_LNG = 121.4737
local DEFAULT_TZID = "Asia/Shanghai"

local a = type(args) == "table" and args or {}

local function read_number(name, default_value, min_value, max_value)
    local value = a[name]
    if value == nil then
        return default_value
    end
    if type(value) ~= "number" then
        error("args." .. name .. " must be a number")
    end
    if value < min_value or value > max_value then
        error(string.format("args.%s must be in [%s, %s]", name, tostring(min_value), tostring(max_value)))
    end
    return value
end

local function read_date()
    local value = a.date
    if value == nil or value == "" then
        return "today"
    end
    if type(value) ~= "string" then
        error("args.date must be a string")
    end
    if value == "today" or value == "tomorrow" or value == "yesterday" then
        return value
    end
    if value:match("^%d%d%d%d%-%d%d%-%d%d$") then
        return value
    end
    error("args.date must be YYYY-MM-DD, today, tomorrow, or yesterday")
end

local function read_tzid()
    local value = a.tzid
    if value == nil or value == "" then
        return DEFAULT_TZID
    end
    if type(value) ~= "string" then
        error("args.tzid must be a string")
    end
    if value:match("^[A-Za-z0-9_+%-%/]+$") == nil then
        error("args.tzid contains unsupported characters")
    end
    return value
end

local function read_formatted()
    local value = a.formatted
    if value == nil then
        return 0
    end
    if type(value) ~= "number" then
        error("args.formatted must be 0 or 1")
    end
    local normalized = math.floor(value)
    if normalized ~= 0 and normalized ~= 1 then
        error("args.formatted must be 0 or 1")
    end
    return normalized
end

local function trim_decimal(value)
    local text = string.format("%.8f", value)
    text = text:gsub("0+$", "")
    text = text:gsub("%.$", "")
    return text
end

local function url_encode(value)
    return tostring(value):gsub("([^%w%-_%.~])", function(ch)
        return string.format("%%%02X", string.byte(ch))
    end)
end

local function build_url(lat, lng, date, formatted, tzid)
    local params = {
        "lat=" .. trim_decimal(lat),
        "lng=" .. trim_decimal(lng),
        "date=" .. url_encode(date),
        "formatted=" .. tostring(formatted),
    }

    if tzid then
        params[#params + 1] = "tzid=" .. url_encode(tzid)
    end

    return API_URL .. "?" .. table.concat(params, "&")
end

local function parse_http_output(out)
    local first_line, body = tostring(out or ""):match("^(.-)\n(.*)$")
    if not first_line then
        first_line = tostring(out or "")
        body = ""
    end

    local status = tonumber(first_line:match("^HTTP%s+(%d+)"))
    if not status then
        error("unexpected http_request output: " .. tostring(out))
    end

    return status, body
end

local function call_http(url)
    local ok, out, err = capability.call("http_request", {
        url = url,
        method = "GET",
        timeout_ms = HTTP_TIMEOUT_MS,
        max_body_bytes = HTTP_MAX_BODY_BYTES,
    }, {
        source_cap = SKILL_ID,
    })

    if not ok then
        local text = tostring(err or out or "unknown error")
        if text:find("HTTP allowlist is empty", 1, true) or
                text:find("is not in allowlist", 1, true) then
            error(text .. ". Add api.sunrise-sunset.org to the HTTP allowlist and try again.")
        end
        error(text)
    end

    return tostring(out or "")
end

local function format_day_length(value)
    if type(value) == "number" then
        local total = math.floor(value)
        local hours = math.floor(total / 3600)
        local minutes = math.floor((total % 3600) / 60)
        local seconds = total % 60
        return string.format("%02d:%02d:%02d", hours, minutes, seconds)
    end
    return tostring(value or "")
end

local function run()
    local lat = read_number("lat", DEFAULT_LAT, -90, 90)
    local lng = read_number("lng", DEFAULT_LNG, -180, 180)
    local date = read_date()
    local tzid = read_tzid()
    local formatted = read_formatted()
    local url = build_url(lat, lng, date, formatted, tzid)

    local out = call_http(url)
    local http_status, body = parse_http_output(out)
    if http_status ~= 200 then
        error(string.format("sunrise-sunset API HTTP %d: %s", http_status, body))
    end

    local ok, payload = pcall(json.decode, body)
    if not ok or type(payload) ~= "table" then
        error("failed to decode sunrise-sunset API JSON response")
    end

    local api_status = tostring(payload.status or "")
    if api_status ~= "OK" and api_status ~= "INVALID_TZID" then
        error("sunrise-sunset API returned status " .. api_status)
    end

    if type(payload.results) ~= "table" then
        error("sunrise-sunset API response missing results")
    end

    local returned_tzid = tostring(payload.tzid or tzid or "UTC")
    local warning = nil
    if api_status == "INVALID_TZID" then
        warning = "Invalid tzid; API returned UTC times."
    end

    local result = {
        skill = SKILL_ID,
        request = {
            lat = lat,
            lng = lng,
            date = date,
            formatted = formatted,
            tzid = tzid,
            url = url,
        },
        http_status = http_status,
        api_status = api_status,
        tzid = returned_tzid,
        results = payload.results,
        summary_zh = string.format(
            "坐标(%s, %s)在%s的日出时间为%s，日落时间为%s，太阳正午为%s，白昼长度为%s，返回时区为%s。",
            trim_decimal(lat),
            trim_decimal(lng),
            date,
            tostring(payload.results.sunrise or ""),
            tostring(payload.results.sunset or ""),
            tostring(payload.results.solar_noon or ""),
            format_day_length(payload.results.day_length),
            returned_tzid
        ),
    }

    if warning then
        result.warning = warning
    end

    print(json.encode(result))
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
    print("[" .. SKILL_ID .. "] ERROR: " .. tostring(err))
    error(err)
end
