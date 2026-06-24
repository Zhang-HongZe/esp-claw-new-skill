local json = require("json")

local SKILL_ID = "suncal"

local PI = math.pi
local sin = math.sin
local cos = math.cos
local tan = math.tan
local asin = math.asin
local acos = math.acos
local atan = math.atan
local sqrt = math.sqrt
local abs = math.abs
local floor = math.floor
local ceil = math.ceil

local rad = PI / 180
local day_s = 86400
local earth_radius = 6378.14
local J2000_UNIX_DAYS = 10957

local SUN_TIME_DEFS = {
    {-0.833, "sunrise", "sunset"},
    {-0.3, "sunriseEnd", "sunsetStart"},
    {-6, "dawn", "dusk"},
    {-12, "nauticalDawn", "nauticalDusk"},
    {-18, "nightEnd", "night"},
    {6, "goldenHourEnd", "goldenHour"},
}

local MOON_LON = {
    0, 0, 1, 0, 6288774, -20905355,
    2, 0, -1, 0, 1274027, -3699111,
    2, 0, 0, 0, 658314, -2955968,
    0, 0, 2, 0, 213618, -569925,
    0, 1, 0, 0, -185116, 48888,
    0, 0, 0, 2, -114332, -3149,
    2, 0, -2, 0, 58793, 246158,
    2, -1, -1, 0, 57066, -152138,
    2, 0, 1, 0, 53322, -170733,
    2, -1, 0, 0, 45758, -204586,
    0, 1, -1, 0, -40923, -129620,
    1, 0, 0, 0, -34720, 108743,
    0, 1, 1, 0, -30383, 104755,
    2, 0, 0, -2, 15327, 10321,
    0, 0, 1, 2, -12528, 0,
    0, 0, 1, -2, 10980, 79661,
    4, 0, -1, 0, 10675, -34782,
    0, 0, 3, 0, 10034, -23210,
    4, 0, -2, 0, 8548, -21636,
    2, 1, -1, 0, -7888, 24208,
    2, 1, 0, 0, -6766, 30824,
    1, 0, -1, 0, -5163, -8379,
    1, 1, 0, 0, 4987, -16675,
    2, -1, 1, 0, 4036, -12831,
    2, 0, 2, 0, 3994, -10445,
    4, 0, 0, 0, 3861, -11650,
    2, 0, -3, 0, 3665, 14403,
    0, 1, -2, 0, -2689, -7003,
    2, 0, -1, 2, -2602, 0,
    2, -1, -2, 0, 2390, 10056,
    1, 0, 1, 0, -2348, 6322,
    2, -2, 0, 0, 2236, -9884,
    0, 1, 2, 0, -2120, 5751,
    0, 2, 0, 0, -2069, 0,
    2, -2, -1, 0, 2048, -4950,
    2, 0, 1, -2, -1773, 4130,
    2, 0, 0, 2, -1595, 0,
    4, -1, -1, 0, 1215, -3958,
    0, 0, 2, 2, -1110, 0,
    3, 0, -1, 0, -892, 3258,
    2, 1, 1, 0, -810, 2616,
    4, -1, -2, 0, 759, -1897,
    0, 2, -1, 0, -713, -2117,
    2, 2, -1, 0, -700, 2354,
    2, 1, -2, 0, 691, 0,
    2, -1, 0, -2, 596, 0,
    4, 0, 1, 0, 549, -1423,
    0, 0, 4, 0, 537, -1117,
    4, -1, 0, 0, 520, -1571,
    1, 0, -2, 0, -487, -1739,
    2, 1, 0, -2, -399, 0,
    0, 0, 2, -2, -381, -4421,
    1, 1, 1, 0, 351, 0,
    3, 0, -2, 0, -340, 0,
    4, 0, -3, 0, 330, 0,
    2, -1, 2, 0, 327, 0,
    0, 2, 1, 0, -323, 1165,
    1, 1, -1, 0, 299, 0,
    2, 0, 3, 0, 294, 0,
    2, 0, -1, -2, 0, 8752,
}

local MOON_LAT = {
    0, 0, 0, 1, 5128122,
    0, 0, 1, 1, 280602,
    0, 0, 1, -1, 277693,
    2, 0, 0, -1, 173237,
    2, 0, -1, 1, 55413,
    2, 0, -1, -1, 46271,
    2, 0, 0, 1, 32573,
    0, 0, 2, 1, 17198,
    2, 0, 1, -1, 9266,
    0, 0, 2, -1, 8822,
    2, -1, 0, -1, 8216,
    2, 0, -2, -1, 4324,
    2, 0, 1, 1, 4200,
    2, 1, 0, -1, -3359,
    2, -1, -1, 1, 2463,
    2, -1, 0, 1, 2211,
    2, -1, -1, -1, 2065,
    0, 1, -1, -1, -1870,
    4, 0, -1, -1, 1828,
    0, 1, 0, 1, -1794,
    0, 0, 0, 3, -1749,
    0, 1, -1, 1, -1565,
    1, 0, 0, 1, -1491,
    0, 1, 1, 1, -1475,
    0, 1, 1, -1, -1410,
    0, 1, 0, -1, -1344,
    1, 0, 0, -1, -1335,
    0, 0, 3, 1, 1107,
    4, 0, 0, -1, 1021,
    4, 0, -1, 1, 833,
    0, 0, 1, -3, 777,
    4, 0, -2, 1, 671,
    2, 0, 0, -3, 607,
    2, 0, 2, -1, 596,
    2, -1, 1, -1, 491,
    2, 0, -2, 1, -451,
    0, 0, 3, -1, 439,
    2, 0, 2, 1, 422,
    2, 0, -3, -1, 421,
    2, 1, -1, 1, -366,
    2, 1, 0, 1, -351,
    4, 0, 0, 1, 331,
    2, -1, 1, 1, 315,
    2, -2, 0, -1, 302,
    0, 0, 1, 3, -283,
    2, 1, 1, -1, -229,
    1, 1, 0, -1, 223,
    1, 1, 0, 1, 223,
    0, 1, -2, -1, -220,
    2, 1, -1, -1, -220,
    1, 0, 1, 1, -185,
    2, -1, -2, -1, 181,
    0, 1, 2, 1, -177,
    4, 0, -2, -1, 176,
    4, -1, -1, -1, 166,
    1, 0, 1, -1, -164,
    4, 0, 1, -1, 132,
    1, 0, -1, -1, -119,
    4, -1, 0, -1, 115,
    2, -2, 0, 1, 107,
}

local a = type(args) == "table" and args or {}

local function round_nearest(value)
    if value >= 0 then
        return floor(value + 0.5)
    end
    return ceil(value - 0.5)
end

local function atan2(y, x)
    return atan(y, x)
end

local function is_nan(value)
    return value ~= value
end

local function trim_decimal(value)
    local text = string.format("%.8f", value)
    text = text:gsub("0+$", "")
    text = text:gsub("%.$", "")
    return text
end

local function require_number(name, min_value, max_value)
    local value = a[name]
    if type(value) ~= "number" then
        error("args." .. name .. " is required and must be a number")
    end
    if value < min_value or value > max_value then
        error(string.format("args.%s must be in [%s, %s]", name, tostring(min_value), tostring(max_value)))
    end
    return value
end

local function read_date_spec()
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

local function read_height_m()
    local value = a.height_m
    if value == nil then
        return 0
    end
    if type(value) ~= "number" then
        error("args.height_m must be a number")
    end
    if value < 0 then
        error("args.height_m must be >= 0")
    end
    return value
end

local function read_utc_offset_minutes()
    local value = a.utc_offset_minutes
    if value == nil then
        return nil
    end
    if type(value) ~= "number" or floor(value) ~= value then
        error("args.utc_offset_minutes must be an integer")
    end
    if value < -720 or value > 840 then
        error("args.utc_offset_minutes must be in [-720, 840]")
    end
    return value
end

local function days_from_civil(year, month, day)
    local y = year
    if month <= 2 then
        y = y - 1
    end
    local era = floor(y / 400)
    local yoe = y - era * 400
    local mp = month + (month > 2 and -3 or 9)
    local doy = floor((153 * mp + 2) / 5) + day - 1
    local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function civil_from_days(z)
    z = z + 719468
    local era = floor(z / 146097)
    local doe = z - era * 146097
    local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
    local mp = floor((5 * doy + 2) / 153)
    local day = doy - floor((153 * mp + 2) / 5) + 1
    local month = mp < 10 and mp + 3 or mp - 9
    if month <= 2 then
        y = y + 1
    end
    return y, month, day
end

local function shift_civil_date(year, month, day, delta_days)
    local days = days_from_civil(year, month, day)
    return civil_from_days(days + delta_days)
end

local function unix_seconds_from_utc_civil(year, month, day, hour, minute, second)
    return days_from_civil(year, month, day) * day_s + hour * 3600 + minute * 60 + second
end

local function split_utc_seconds(seconds)
    local days = floor(seconds / day_s)
    local sod = seconds - days * day_s
    local year, month, day = civil_from_days(days)
    local hour = floor(sod / 3600)
    local minute = floor((sod % 3600) / 60)
    local second = sod % 60
    return year, month, day, hour, minute, second
end

local function format_civil_date(year, month, day)
    return string.format("%04d-%02d-%02d", year, month, day)
end

local function parse_date_string(value)
    local year, month, day = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not year then
        error("invalid date string")
    end

    year = tonumber(year)
    month = tonumber(month)
    day = tonumber(day)
    if month < 1 or month > 12 then
        error("args.date month must be in [1, 12]")
    end
    if day < 1 or day > 31 then
        error("args.date day must be in [1, 31]")
    end

    local check_year, check_month, check_day = civil_from_days(days_from_civil(year, month, day))
    if check_year ~= year or check_month ~= month or check_day ~= day then
        error("args.date is not a valid calendar date")
    end

    return year, month, day
end

local function relative_day_delta(date_spec)
    if date_spec == "today" then
        return 0
    end
    if date_spec == "tomorrow" then
        return 1
    end
    if date_spec == "yesterday" then
        return -1
    end
    return nil
end

local function resolve_civil_date(date_spec, utc_offset_minutes)
    local delta = relative_day_delta(date_spec)
    if utc_offset_minutes ~= nil then
        if delta == nil then
            return parse_date_string(date_spec)
        end
        local now_s = os.time()
        local shifted_days = floor((now_s + utc_offset_minutes * 60) / day_s)
        local year, month, day = civil_from_days(shifted_days)
        return shift_civil_date(year, month, day, delta)
    end

    if delta == nil then
        return parse_date_string(date_spec)
    end

    local now = os.date("*t")
    return shift_civil_date(now.year, now.month, now.day, delta)
end

local function require_local_epoch(year, month, day, hour, minute, second)
    local epoch = os.time({
        year = year,
        month = month,
        day = day,
        hour = hour,
        min = minute,
        sec = second,
    })
    if type(epoch) ~= "number" then
        error("failed to build local epoch time")
    end
    return epoch
end

local function resolve_runtime(date_spec, utc_offset_minutes)
    local year, month, day = resolve_civil_date(date_spec, utc_offset_minutes)
    local resolved_date = format_civil_date(year, month, day)

    if utc_offset_minutes ~= nil then
        local sun_anchor_s = unix_seconds_from_utc_civil(year, month, day, 12, 0, 0) - utc_offset_minutes * 60
        local moon_window_start_s = unix_seconds_from_utc_civil(year, month, day, 0, 0, 0) - utc_offset_minutes * 60
        return {
            resolved_date = resolved_date,
            year = year,
            month = month,
            day = day,
            sun_anchor_s = sun_anchor_s,
            moon_window_start_s = moon_window_start_s,
            output_mode = "offset",
            utc_offset_minutes = utc_offset_minutes,
        }
    end

    return {
        resolved_date = resolved_date,
        year = year,
        month = month,
        day = day,
        sun_anchor_s = require_local_epoch(year, month, day, 12, 0, 0),
        moon_window_start_s = require_local_epoch(year, month, day, 0, 0, 0),
        output_mode = "device_local",
    }
end

local function format_offset_label(offset_minutes)
    local sign = offset_minutes >= 0 and "+" or "-"
    local total = abs(offset_minutes)
    return string.format("UTC%s%02d:%02d", sign, floor(total / 60), total % 60)
end

local function format_iso_utc(epoch_s)
    local year, month, day, hour, minute, second = split_utc_seconds(epoch_s)
    return string.format("%04d-%02d-%02dT%02d:%02d:%02dZ", year, month, day, hour, minute, second)
end

local function format_iso_with_offset(epoch_s, offset_minutes)
    local shifted = epoch_s + offset_minutes * 60
    local year, month, day, hour, minute, second = split_utc_seconds(shifted)
    local sign = offset_minutes >= 0 and "+" or "-"
    local total = abs(offset_minutes)
    return string.format(
        "%04d-%02d-%02dT%02d:%02d:%02d%s%02d:%02d",
        year,
        month,
        day,
        hour,
        minute,
        second,
        sign,
        floor(total / 60),
        total % 60
    )
end

local function get_local_offset_seconds(epoch_s)
    local local_t = os.date("*t", epoch_s)
    local utc_t = os.date("!*t", epoch_s)
    utc_t.isdst = local_t.isdst
    return os.difftime(os.time(local_t), os.time(utc_t))
end

local function encode_event(epoch_s, runtime)
    if epoch_s == nil then
        return {
            exists = false,
        }
    end

    local item = {
        exists = true,
        unix_s = epoch_s,
        utc_iso = format_iso_utc(epoch_s),
    }

    if runtime.output_mode == "offset" then
        item.local_iso = format_iso_with_offset(epoch_s, runtime.utc_offset_minutes)
        item.local_offset_minutes = runtime.utc_offset_minutes
        item.local_timezone = format_offset_label(runtime.utc_offset_minutes)
        return item
    end

    local offset_seconds = get_local_offset_seconds(epoch_s)
    local offset_minutes = round_nearest(offset_seconds / 60)
    item.local_iso = format_iso_with_offset(epoch_s, offset_minutes)
    item.local_offset_minutes = offset_minutes
    item.local_timezone = tostring(os.date("%Z", epoch_s) or "")
    return item
end

local function format_duration(total_seconds)
    local seconds = round_nearest(total_seconds)
    local hours = floor(seconds / 3600)
    local minutes = floor((seconds % 3600) / 60)
    local remain = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, remain)
end

local function to_days_from_epoch_s(epoch_s)
    local unix_days = floor(epoch_s / day_s)
    local sec_of_day = epoch_s - unix_days * day_s
    return (unix_days - J2000_UNIX_DAYS) + sec_of_day / day_s - 0.5
end

local function days_to_epoch_s(day_value, anchor_day, anchor_epoch_s)
    return anchor_epoch_s + round_nearest((day_value - anchor_day) * day_s)
end

local function delta_t(d)
    local year = 2000 + d / 365.2425
    local t
    if year < 1920 then
        t = year - 1900
        return -2.79 + t * (1.494119 + t * (-0.0598939 + t * (0.0061966 - t * 0.000197)))
    end
    if year < 1941 then
        t = year - 1920
        return 21.20 + t * (0.84493 + t * (-0.076100 + t * 0.0020936))
    end
    if year < 1961 then
        t = year - 1950
        return 29.07 + t * (0.407 + t * (-1 / 233 + t / 2547))
    end
    if year < 1986 then
        t = year - 1975
        return 45.45 + t * (1.067 + t * (-1 / 260 - t / 718))
    end
    if year < 2005 then
        t = year - 2000
        return 63.86 + t * (0.3345 + t * (-0.060374 + t * (0.0017275 + t * (0.000651814 + t * 0.00002373599))))
    end
    if year < 2050 then
        t = year - 2000
        return 62.92 + t * (0.32217 + t * 0.005589)
    end
    t = (year - 1820) / 100
    return -20 + 32 * t * t - 0.5628 * (2150 - year)
end

local function to_days_tt(d)
    return d + delta_t(d) / day_s
end

local function azimuth(H, phi, dec)
    return (atan2(sin(H), cos(H) * sin(phi) - tan(dec) * cos(phi)) / rad + 540) % 360
end

local function altitude(H, phi, dec)
    return asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(H))
end

local function sidereal_time(d, lw)
    return rad * (280.46061837 + 360.98564736629 * d) - lw
end

local function astro_refraction(h)
    local altitude_rad = h
    if altitude_rad < 0 then
        altitude_rad = 0
    end
    return 0.0002967 / tan(altitude_rad + 0.00312536 / (altitude_rad + 0.08901179))
end

local function sun_coords(d)
    local t = d / 36525
    local L0 = rad * (280.46646 + t * (36000.76983 + t * 0.0003032))
    local M = rad * (357.52911 + t * (35999.05029 - t * 0.0001537))
    local sinM = sin(M)
    local cosM = cos(M)
    local C = rad * (
        (1.914602 - t * (0.004817 + t * 0.000014)) * sinM +
        (0.019993 - 0.000101 * t) * 2 * sinM * cosM +
        0.000289 * sinM * (3 - 4 * sinM * sinM)
    )
    local Om = rad * (125.04 - 1934.136 * t)
    local L = L0 + C - rad * (0.00569 + 0.00478 * sin(Om))
    local e = rad * (23.439291 - t * (0.0130042 + t * (0.00000016 - t * 0.000000504))) + rad * 0.00256 * cos(Om)

    return {
        ra = atan2(cos(e) * sin(L), cos(L)),
        dec = asin(sin(e) * sin(L)),
    }
end

local J0 = 0.0009

local function observer_angle(height)
    return -2.076 * sqrt(height) / 60
end

local function wrap_pi(value)
    return value - 2 * PI * round_nearest(value / (2 * PI))
end

local function solar_transit(dt, lw)
    local d = dt
    for _ = 1, 3 do
        local H = wrap_pi(sidereal_time(d, lw) - sun_coords(to_days_tt(d)).ra)
        d = d - H / (2 * PI)
    end
    return d
end

local function get_set_j(h0, dt, sign, lw, phi, dec_t)
    local cosH0 = (sin(h0) - sin(phi) * sin(dec_t)) / (cos(phi) * cos(dec_t))
    if cosH0 < -1 or cosH0 > 1 then
        return nil
    end

    local d = dt + sign * acos(cosH0) / (2 * PI)
    for _ = 1, 2 do
        local c = sun_coords(to_days_tt(d))
        local H = wrap_pi(sidereal_time(d, lw) - c.ra)
        local h = altitude(H, phi, c.dec)
        local sinH = cos(phi) * cos(c.dec) * sin(H)
        if abs(sinH) < 1e-6 then
            break
        end
        d = d + (h - h0) / (2 * PI * sinH)
    end
    return d
end

local function get_sun_times(anchor_day, lat, lng, height)
    local lw = rad * -lng
    local phi = rad * lat
    local dh = observer_angle(height)
    local d = round_nearest(round_nearest(anchor_day) - J0 - lw / (2 * PI))
    local dt = solar_transit(d + J0 + lw / (2 * PI), lw)
    local dec = sun_coords(to_days_tt(dt)).dec

    local result = {
        solarNoon = dt,
        nadir = dt - 0.5,
    }

    for _, def in ipairs(SUN_TIME_DEFS) do
        local angle = def[1]
        local rise_name = def[2]
        local set_name = def[3]
        local h0 = (angle + dh) * rad
        local jrise = get_set_j(h0, dt, -1, lw, phi, dec)
        local jset = get_set_j(h0, dt, 1, lw, phi, dec)
        result[rise_name] = jrise
        result[set_name] = jset
    end

    if result.sunrise == nil then
        local noon_alt = altitude(0, phi, dec)
        local rise_set_alt = (SUN_TIME_DEFS[1][1] + dh) * rad
        result.alwaysUp = noon_alt > rise_set_alt
        result.alwaysDown = noon_alt <= rise_set_alt
    end

    return result
end

local function nutation_obliquity(t)
    local om = rad * (125.04452 - 1934.136261 * t)
    local ls = rad * (280.4665 + 36000.7698 * t)
    local lm = rad * (218.3165 + 481267.8813 * t)
    local dpsi = (-17.20 * sin(om) - 1.32 * sin(2 * ls) - 0.23 * sin(2 * lm) + 0.21 * sin(2 * om)) / 3600
    local deps = (9.20 * cos(om) + 0.57 * cos(2 * ls) + 0.10 * cos(2 * lm) - 0.09 * cos(2 * om)) / 3600
    local eps0 = 23.439291 - t * (0.0130042 + t * (0.00000016 - t * 0.000000504))
    return {
        dpsi = dpsi,
        eps = rad * (eps0 + deps),
    }
end

local function moon_coords(d)
    local t = d / 36525
    local Lp = 218.3164477 + t * (481267.88123421 + t * (-0.0015786 + t * (1 / 538841 - t / 65194000)))
    local D = 297.8501921 + t * (445267.1114034 + t * (-0.0018819 + t * (1 / 545868 - t / 113065000)))
    local M = 357.5291092 + t * (35999.0502909 + t * (-0.0001536 + t / 24490000))
    local Mp = 134.9633964 + t * (477198.8675055 + t * (0.0087414 + t * (1 / 69699 - t / 14712000)))
    local F = 93.2720950 + t * (483202.0175233 + t * (-0.0036539 + t * (-1 / 3526000 + t / 863310000)))
    local A1 = 119.75 + 131.849 * t
    local A2 = 53.09 + 479264.290 * t
    local A3 = 313.45 + 481266.484 * t
    local E = 1 - t * (0.002516 + t * 0.0000074)

    local Dr = rad * D
    local Mr = rad * M
    local Mpr = rad * Mp
    local Fr = rad * F
    local sl = 0
    local sr = 0
    local sb = 0

    for i = 1, #MOON_LON, 6 do
        local m = MOON_LON[i + 1]
        local arg = MOON_LON[i] * Dr + m * Mr + MOON_LON[i + 2] * Mpr + MOON_LON[i + 3] * Fr
        local factor = 1
        if m == 1 or m == -1 then
            factor = E
        elseif m == 2 or m == -2 then
            factor = E * E
        end
        sl = sl + MOON_LON[i + 4] * factor * sin(arg)
        sr = sr + MOON_LON[i + 5] * factor * cos(arg)
    end

    for i = 1, #MOON_LAT, 5 do
        local m = MOON_LAT[i + 1]
        local arg = MOON_LAT[i] * Dr + m * Mr + MOON_LAT[i + 2] * Mpr + MOON_LAT[i + 3] * Fr
        local factor = 1
        if m == 1 or m == -1 then
            factor = E
        elseif m == 2 or m == -2 then
            factor = E * E
        end
        sb = sb + MOON_LAT[i + 4] * factor * sin(arg)
    end

    local A1r = rad * A1
    local Lpr = rad * Lp
    sl = sl + 3958 * sin(A1r) + 1962 * sin(Lpr - Fr) + 318 * sin(rad * A2)
    sb = sb - 2235 * sin(Lpr) + 382 * sin(rad * A3) + 175 * sin(A1r - Fr) + 175 * sin(A1r + Fr) +
        127 * sin(Lpr - Mpr) - 115 * sin(Lpr + Mpr)

    local nutation = nutation_obliquity(t)
    local l = rad * (Lp + sl / 1e6 + nutation.dpsi)
    local b = rad * (sb / 1e6)

    return {
        ra = atan2(sin(l) * cos(nutation.eps) - tan(b) * sin(nutation.eps), cos(l)),
        dec = asin(sin(b) * cos(nutation.eps) + cos(b) * sin(nutation.eps) * sin(l)),
        dist = 385000.56 + sr / 1000,
    }
end

local function get_moon_position(day_value, lat, lng)
    local lw = rad * -lng
    local phi = rad * lat
    local d = day_value
    local c = moon_coords(to_days_tt(d))
    local H = sidereal_time(d, lw) - c.ra
    local h_geo = altitude(H, phi, c.dec)
    local h = h_geo - asin(earth_radius / c.dist * cos(h_geo))
    local pa = atan2(sin(H), tan(phi) * cos(c.dec) - sin(c.dec) * cos(H))

    return {
        azimuth = azimuth(H, phi, c.dec),
        altitude = (h + astro_refraction(h)) / rad,
        distance = c.dist,
        parallacticAngle = pa / rad,
    }
end

local function get_moon_illumination(day_value)
    local d = to_days_tt(day_value)
    local sun = sun_coords(d)
    local moon = moon_coords(d)
    local sun_dist = 149598000
    local phi = acos(sin(sun.dec) * sin(moon.dec) + cos(sun.dec) * cos(moon.dec) * cos(sun.ra - moon.ra))
    local inc = atan2(sun_dist * sin(phi), moon.dist - sun_dist * cos(phi))
    local angle = atan2(
        cos(sun.dec) * sin(sun.ra - moon.ra),
        sin(sun.dec) * cos(moon.dec) - cos(sun.dec) * sin(moon.dec) * cos(sun.ra - moon.ra)
    )
    local waxing = angle < 0

    return {
        fraction = (1 + cos(inc)) / 2,
        phase = 0.5 + 0.5 * inc * (waxing and -1 or 1) / PI,
        angle = angle / rad,
        waxing = waxing,
    }
end

local function hours_later_day(day_value, hours)
    return day_value + hours / 24
end

local function moon_height(day_value, lat, lng)
    local position = get_moon_position(day_value, lat, lng)
    return position.altitude + 0.2725 * asin(earth_radius / position.distance) / rad + 0.09
end

local function refine_moon_cross(day_value, lat, lng)
    local value = day_value
    for _ = 1, 2 do
        local h = moon_height(value, lat, lng)
        local step_day = 30 / day_s
        local dh = (moon_height(value + step_day, lat, lng) - moon_height(value - step_day, lat, lng)) / 60
        if abs(dh) < 1e-9 or is_nan(dh) then
            break
        end
        value = value - h / dh
    end
    return value
end

local function get_moon_times(window_start_day, lat, lng)
    local h0 = moon_height(window_start_day, lat, lng)
    local rise
    local set
    local ye = h0

    for i = 1, 24, 2 do
        local h1 = moon_height(hours_later_day(window_start_day, i), lat, lng)
        local h2 = moon_height(hours_later_day(window_start_day, i + 1), lat, lng)
        local qa = (h0 + h2) / 2 - h1
        local qb = (h2 - h0) / 2
        local xe = -qb / (2 * qa)
        local discriminant = qb * qb - 4 * qa * h1
        local roots = 0
        local x1 = 0
        local x2 = 0
        ye = (qa * xe + qb) * xe + h1

        if discriminant >= 0 then
            local dx = sqrt(discriminant) / (abs(qa) * 2)
            x1 = xe - dx
            x2 = xe + dx
            if abs(x1) <= 1 then
                roots = roots + 1
            end
            if abs(x2) <= 1 then
                roots = roots + 1
            end
            if x1 < -1 then
                x1 = x2
            end
        end

        if roots == 1 then
            if h0 < 0 then
                rise = i + x1
            else
                set = i + x1
            end
        elseif roots == 2 then
            rise = i + (ye < 0 and x2 or x1)
            set = i + (ye < 0 and x1 or x2)
        end

        if rise ~= nil and set ~= nil then
            break
        end

        h0 = h2
    end

    local result = {}
    if rise ~= nil then
        result.rise = refine_moon_cross(hours_later_day(window_start_day, rise), lat, lng)
    end
    if set ~= nil then
        result.set = refine_moon_cross(hours_later_day(window_start_day, set), lat, lng)
    end
    if rise == nil and set == nil then
        result.alwaysUp = ye > 0
        result.alwaysDown = ye <= 0
    end

    return result
end

local function moon_phase_name_zh(phase)
    local names = {
        "新月",
        "娥眉月",
        "上弦月",
        "盈凸月",
        "满月",
        "亏凸月",
        "下弦月",
        "残月",
    }
    local idx = (round_nearest(phase * 8) % 8) + 1
    return names[idx]
end

local function build_sun_output(sun, runtime, sun_anchor_day)
    local result = {
        sunrise = encode_event(sun.sunrise and days_to_epoch_s(sun.sunrise, sun_anchor_day, runtime.sun_anchor_s) or nil, runtime),
        sunriseEnd = encode_event(sun.sunriseEnd and days_to_epoch_s(sun.sunriseEnd, sun_anchor_day, runtime.sun_anchor_s) or nil, runtime),
        goldenHourEnd = encode_event(sun.goldenHourEnd and days_to_epoch_s(sun.goldenHourEnd, sun_anchor_day, runtime.sun_anchor_s) or nil, runtime),
        solarNoon = encode_event(sun.solarNoon and days_to_epoch_s(sun.solarNoon, sun_anchor_day, runtime.sun_anchor_s) or nil, runtime),
        goldenHour = encode_event(sun.goldenHour and days_to_epoch_s(sun.goldenHour, sun_anchor_day, runtime.sun_anchor_s) or nil, runtime),
        sunsetStart = encode_event(sun.sunsetStart and days_to_epoch_s(sun.sunsetStart, sun_anchor_day, runtime.sun_anchor_s) or nil, runtime),
        sunset = encode_event(sun.sunset and days_to_epoch_s(sun.sunset, sun_anchor_day, runtime.sun_anchor_s) or nil, runtime),
        dusk = encode_event(sun.dusk and days_to_epoch_s(sun.dusk, sun_anchor_day, runtime.sun_anchor_s) or nil, runtime),
        nauticalDusk = encode_event(sun.nauticalDusk and days_to_epoch_s(sun.nauticalDusk, sun_anchor_day, runtime.sun_anchor_s) or nil, runtime),
        night = encode_event(sun.night and days_to_epoch_s(sun.night, sun_anchor_day, runtime.sun_anchor_s) or nil, runtime),
        nightEnd = encode_event(sun.nightEnd and days_to_epoch_s(sun.nightEnd, sun_anchor_day, runtime.sun_anchor_s) or nil, runtime),
        nauticalDawn = encode_event(sun.nauticalDawn and days_to_epoch_s(sun.nauticalDawn, sun_anchor_day, runtime.sun_anchor_s) or nil, runtime),
        dawn = encode_event(sun.dawn and days_to_epoch_s(sun.dawn, sun_anchor_day, runtime.sun_anchor_s) or nil, runtime),
        nadir = encode_event(sun.nadir and days_to_epoch_s(sun.nadir, sun_anchor_day, runtime.sun_anchor_s) or nil, runtime),
        alwaysUp = sun.alwaysUp == true,
        alwaysDown = sun.alwaysDown == true,
    }

    if sun.sunrise ~= nil and sun.sunset ~= nil then
        local seconds = round_nearest((sun.sunset - sun.sunrise) * day_s)
        result.dayLengthSeconds = seconds
        result.dayLengthText = format_duration(seconds)
    end

    return result
end

local function build_moon_output(moon_times, illumination, runtime, moon_anchor_day)
    return {
        rise = encode_event(moon_times.rise and days_to_epoch_s(moon_times.rise, moon_anchor_day, runtime.moon_window_start_s) or nil, runtime),
        set = encode_event(moon_times.set and days_to_epoch_s(moon_times.set, moon_anchor_day, runtime.moon_window_start_s) or nil, runtime),
        alwaysUp = moon_times.alwaysUp == true,
        alwaysDown = moon_times.alwaysDown == true,
        illumination = {
            fraction = illumination.fraction,
            phase = illumination.phase,
            angle = illumination.angle,
            waxing = illumination.waxing,
            phaseNameZh = moon_phase_name_zh(illumination.phase),
        },
    }
end

local function event_text(label, event)
    if not event or event.exists ~= true then
        return label .. "无"
    end
    return label .. event.local_iso
end

local function build_summary(lat, lng, runtime, sun_output, moon_output)
    local sun_text
    if sun_output.alwaysUp then
        sun_text = "太阳全天不落"
    elseif sun_output.alwaysDown then
        sun_text = "太阳全天不升"
    else
        local day_length = sun_output.dayLengthText and ("，白昼长度 " .. sun_output.dayLengthText) or ""
        sun_text = event_text("日出 ", sun_output.sunrise) ..
            "，" .. event_text("日落 ", sun_output.sunset) ..
            "，" .. event_text("太阳正午 ", sun_output.solarNoon) ..
            day_length
    end

    local moon_text
    if moon_output.alwaysUp then
        moon_text = "月亮全天在地平线上方"
    elseif moon_output.alwaysDown then
        moon_text = "月亮全天在地平线下方"
    else
        moon_text = event_text("月升 ", moon_output.rise) .. "，" .. event_text("月落 ", moon_output.set)
    end

    local time_basis
    if runtime.output_mode == "offset" then
        time_basis = "本地时间按 " .. format_offset_label(runtime.utc_offset_minutes) .. " 输出。"
    else
        time_basis = "未传 utc_offset_minutes，本地时间按设备当前时区输出。"
    end

    return string.format(
        "%s 坐标(%s, %s)：%s；%s；月相为%s，照明比例约%.1f%%。%s",
        runtime.resolved_date,
        trim_decimal(lat),
        trim_decimal(lng),
        sun_text,
        moon_text,
        moon_output.illumination.phaseNameZh,
        moon_output.illumination.fraction * 100,
        time_basis
    )
end

local function run()
    local lat = require_number("lat", -90, 90)
    local lng = require_number("lng", -180, 180)
    local date_spec = read_date_spec()
    local height_m = read_height_m()
    local utc_offset_minutes = read_utc_offset_minutes()

    local runtime = resolve_runtime(date_spec, utc_offset_minutes)
    local sun_anchor_day = to_days_from_epoch_s(runtime.sun_anchor_s)
    local moon_anchor_day = to_days_from_epoch_s(runtime.moon_window_start_s)
    local sun_times = get_sun_times(sun_anchor_day, lat, lng, height_m)
    local moon_times = get_moon_times(moon_anchor_day, lat, lng)
    local illumination = get_moon_illumination(sun_anchor_day)

    local sun_output = build_sun_output(sun_times, runtime, sun_anchor_day)
    local moon_output = build_moon_output(moon_times, illumination, runtime, moon_anchor_day)

    local result = {
        skill = SKILL_ID,
        implementation = {
            mode = "local_compute",
            api_calls = false,
        },
        request = {
            lat = lat,
            lng = lng,
            date = date_spec,
            resolved_date = runtime.resolved_date,
            height_m = height_m,
            utc_offset_minutes = utc_offset_minutes,
            output_mode = runtime.output_mode,
        },
        sun = sun_output,
        moon = moon_output,
        summary_zh = build_summary(lat, lng, runtime, sun_output, moon_output),
    }

    print(json.encode(result))
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
    print("[" .. SKILL_ID .. "] ERROR: " .. tostring(err))
    error(err)
end
