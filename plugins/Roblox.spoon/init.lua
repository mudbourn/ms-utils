--- === Roblox ===
--- Roblox target + live settings reader + anti-timeout + cache cleaner.
--- See README.md for behaviour and rationale.

local obj = {}
obj.__index = obj

obj.name    = "Roblox"
obj.version = "0.1.0"
obj.author  = "mudbourn"
obj.license = "MIT"

-- Paths --
    local ROBLOX_DIR   = os.getenv("HOME") .. "/Library/Roblox"
    local SETTINGS_XML = ROBLOX_DIR .. "/GlobalBasicSettings_13.xml"
    local CACHE_LABEL  = "com.mudscript.cache-cleaner"
-- END Paths --

-- Settings Reader --
    local function readSetting(key)
        if type(key) ~= "string" then return nil end
        local f = io.open(SETTINGS_XML, "r")
        if not f then return nil end
        local data = f:read("*a")
        f:close()
        if not data then return nil end
        return data:match('name="' .. key .. '"[^>]*>([^<]*)<')
    end

    local function readNumber(key)
        return tonumber(readSetting(key))
    end

    local function readBool(key)
        local v = readSetting(key)
        if v == nil then return nil end
        return v == "true"
    end
-- END Settings Reader --

-- Cache Cleaner --
    local function bundleDir()
        local src = debug.getinfo(1, "S").source
        local dir = src and src:match("^@(.*)/[^/]+$")
        if dir then return dir end
        return os.getenv("HOME") .. "/.hammerspoon/Spoons/Roblox.spoon"
    end

    local function litPattern(s) return (s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")) end
    local function litRepl(s) return (s:gsub("%%", "%%%%")) end

    local function syncCacheCleaner(enabled)
        local home      = os.getenv("HOME")
        local dir       = bundleDir()
        local scriptSrc = dir .. "/bin/clean_roblox_cache.sh"
        local plistSrc  = dir .. "/bin/" .. CACHE_LABEL .. ".plist"
        local plistDst  = home .. "/Library/LaunchAgents/" .. CACHE_LABEL .. ".plist"
        if enabled then
            if hs.fs.attributes(plistSrc) and hs.fs.attributes(scriptSrc) then
                local f = io.open(plistSrc, "r")
                if f then
                    local content = f:read("*all"); f:close()
                    content = content:gsub(litPattern("%%AGENT_PATH%%"), litRepl(scriptSrc))
                    local g = io.open(plistDst, "w")
                    if g then g:write(content); g:close() end
                    os.execute("chmod 755 '" .. scriptSrc .. "'")
                    os.execute("launchctl unload '" .. plistDst
                        .. "' 2>/dev/null; launchctl load '" .. plistDst .. "'")
                end
            end
        else
            os.execute("launchctl unload '" .. plistDst .. "' 2>/dev/null")
            os.remove(plistDst)
        end
    end
-- END Cache Cleaner --

function obj:init()

    -- Target App --
        ms.setTargetApp("Roblox")
    -- END Target App --

    -- Live Reader (ms.roblox) --
        ms.roblox = {
            setting         = readSetting,
            settingNumber   = readNumber,
            settingBool     = readBool,

            sensitivity     = function() return readNumber("MouseSensitivity") end,
            gamepadSens     = function() return readNumber("GamepadCameraSensitivity") end,
            framerateCap    = function() return readNumber("FramerateCap") end,
            graphicsQuality = function() return readNumber("GraphicsQualityLevel") end,
            savedQuality    = function() return readNumber("SavedQualityLevel") end,
            masterVolume    = function() return readNumber("MasterVolume") end,
            fullscreen      = function() return readBool("Fullscreen") end,
            cameraInverted  = function() return readBool("CameraYInverted") end,

            isFocused = function() return ms._targetActive == true end,
            activate  = function()
                if ms._targetHandle then
                    pcall(function() ms._targetHandle:activate() end)
                end
            end,
        }
    -- END Live Reader --

    -- Anti-Timeout --
        local function armAntiTimeout()
            local enabled = ms.settings.get("robloxAntiTimeout")
            local minutes = ms.settings.get("robloxAntiTimeoutMins") or 15
            ms.antiTimeout({
                enabled  = enabled == true,
                interval = math.max(1, minutes) * 60,
                action   = function() ms.press("f15") end,
            })
        end

        ms.settings.define({
            type    = "toggle",
            key     = "robloxAntiTimeout",
            label   = "Anti-Timeout",
            hint    = "Send a harmless keystroke on an interval to avoid Roblox's idle kick",
            default = false,
            save    = true,
            section = "roblox",
            onChange = function() armAntiTimeout() end,
        })

        ms.settings.define({
            type    = "slider",
            key     = "robloxAntiTimeoutMins",
            label   = "Anti-Timeout Interval (min)",
            min     = 1,
            max     = 19,
            step    = 1,
            default = 15,
            save    = true,
            section = "roblox",
            onChange = function() armAntiTimeout() end,
        })
    -- END Anti-Timeout --

    -- Cache Cleaner Toggle --
        ms.settings.define({
            type    = "toggle",
            key     = "robloxCacheCleaner",
            label   = "Roblox Cache Cleaner",
            hint    = "Auto-purge micro-profiler dumps & stale caches every 6h (launchd agent)",
            default = false,
            save    = true,
            section = "roblox",
            onChange = function(on) pcall(syncCacheCleaner, on == true) end,
        })
    -- END Cache Cleaner Toggle --

    -- Show Settings Action --
        ms.settings.define({
            type    = "action",
            key     = "robloxShowSettings",
            label   = "Show Roblox Settings",
            section = "roblox",
            onAction = function()
                local sens = ms.roblox.sensitivity()
                local fps  = ms.roblox.framerateCap()
                local q    = ms.roblox.graphicsQuality()
                if sens or fps or q then
                    ms.alert(string.format(
                        "Sensitivity: %s   FPS cap: %s   Quality: %s",
                        tostring(sens or "?"), tostring(fps or "?"), tostring(q or "?")), 4)
                else
                    ms.alert("Roblox settings not found.", 3)
                end
            end,
        })
    -- END Show Settings Action --

    -- Builder Tools --
        if ms.tools and ms.tools.define then
            ms.tools.define({
                id   = "roblox.sensitivity",
                name = "Roblox: Mouse Sensitivity",
                run  = function() return ms.roblox.sensitivity() end,
            })

            ms.tools.define({
                id   = "roblox.framerateCap",
                name = "Roblox: Framerate Cap",
                run  = function() return ms.roblox.framerateCap() end,
            })

            ms.tools.define({
                id   = "roblox.isFocused",
                name = "Roblox: Is Focused",
                run  = function() return ms.roblox.isFocused() end,
            })
        end
    -- END Builder Tools --

    armAntiTimeout()
    return self
end

function obj:stop()
    pcall(function() ms.antiTimeoutStop() end)
    if ms._targetApp == "Roblox" then
        pcall(function() ms.setTargetApp(nil) end)
    end
    ms.roblox = nil
    return self
end

return obj
