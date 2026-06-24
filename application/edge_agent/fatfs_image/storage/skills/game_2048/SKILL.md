---
{
  "name": "game_2048",
  "description": "Start a local 2048 web game with swipe up, down, left, and right controls on touch screens. Use this when the user wants to play 2048 in the browser.",
  "metadata": {
    "cap_groups": [
      "cap_lua"
    ],
    "manage_mode": "readonly"
  }
}
---

# 2048 Game

Use this skill when the user wants to play 2048, a sliding number puzzle, or a local swipe-controlled browser game.

Run exactly one bundled Lua script asynchronously with `lua_run_script_async`.

If script execution returns an error, report that error directly to the user.

## Script Args Schema

```json
{
  "type": "object",
  "properties": {
    "app_id": {
      "type": "string",
      "description": "Optional URL-safe app id. Defaults to game_2048."
    },
    "web_root": {
      "type": "string",
      "description": "Optional absolute directory for static web files. Defaults to the skill assets directory under the active storage root."
    }
  }
}
```

## Tool Call Inputs

Default action:

```json
{
  "path": "{CUR_SKILL_DIR}/scripts/start_2048.lua",
  "args": {
    "app_id": "game_2048",
    "web_root": "{CUR_SKILL_DIR}/assets"
  }
}
```

## Recommended Flow

Run the bundled Lua script asynchronously so the local HTTP page stays available:

- Script: `{CUR_SKILL_DIR}/scripts/start_2048.lua`
- Capability: `lua_run_script_async`
- Timeout: `0`
- Name: `game_2048`
- Exclusive: `game_2048`
- Replace: `true`
- Args: optional object

Example args:

```json
{
  "app_id": "game_2048",
  "web_root": "{CUR_SKILL_DIR}/assets"
}
```

After the script starts, open:

```text
/lua/game_2048/
```

Keep the trailing slash. The bundled page supports swipe up, down, left, and right on touch screens, and also supports keyboard arrows, `WASD`, and on-screen direction buttons.

If `app_id` is changed, open `/lua/<app_id>/` with the same trailing slash rule.

Stop the async Lua job when the game page is no longer needed.
