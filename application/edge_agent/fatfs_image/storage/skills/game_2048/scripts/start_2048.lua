local http = require("http_server")
local storage = require("storage")

local DEFAULT_APP_ID = "game_2048"

local a = type(args) == "table" and args or {}

local function safe_app_id(value)
    return type(value) == "string" and value:match("^[%w_-]+$") ~= nil
end

local function safe_abs_path(value)
    return type(value) == "string" and value:sub(1, 1) == "/" and not value:find("%.%.", 1, true)
end

local function resolve_default_web_root()
    local root = storage.get_root_dir()
    return storage.join_path(root, "skills", "game_2048", "assets")
end

local app_id = type(a.app_id) == "string" and a.app_id ~= "" and a.app_id or DEFAULT_APP_ID
local web_root = type(a.web_root) == "string" and a.web_root ~= "" and a.web_root or resolve_default_web_root()

local function run()
    if not safe_app_id(app_id) then
        error("invalid app_id: " .. tostring(app_id))
    end
    if not safe_abs_path(web_root) then
        error("invalid web_root: " .. tostring(web_root))
    end
    if not storage.exists(web_root) then
        error("web_root does not exist: " .. tostring(web_root))
    end

    local app = http.app(app_id)
    app:mount_static(web_root)

    print("[game_2048] serving " .. app:url() .. " from " .. web_root)
    print("[game_2048] swipe on touch screens or use arrow keys / WASD")
    app:serve_forever()
    print("[game_2048] stopped")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
    print("[game_2048] ERROR: " .. tostring(err))
    error(err)
end
