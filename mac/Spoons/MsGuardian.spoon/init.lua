-- mudscript pre-load tamper check — see DOCS_MAC.md § 20 for the full security model.

local _obj = {
    name    = "MsGuardian",
    version = "1.0",
}

-- Paths --
    local _home      = os.getenv("HOME")
    local _corePath  = _home .. "/.hammerspoon/ms_core.lua"
    local _trustPath = _home .. "/.hammerspoon/data/.ms_trusted_hash"
    local _dataPath  = _home .. "/.hammerspoon/data/"

    -- RSA-2048 public key for MANIFEST.json signature verification.
    -- Must match ms._updatePublicKey in ms_core.lua.
    local _publicKey = [[
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3pyxWISHUScKsmK0fyqA
QWUU0nzYEVpRYD+kRkZsL5AGqpjfNqfOky5bacE1jPXgu9LGz+b1pq1tuyZotvK/
FrMeQDCmGWiu5RXAqsyg0iN1c1CHSvWAT40xi6g54u9ot9LMfzmBETlwWd4QoXOA
OnT3KW0aia1EoyUjjNIRk6iv6pxi+BjHnGKoID6pAl9de+WASt/DETgCuKhQ7o/Y
iGn43A9ZutKUfkV+Muu1RcTy62zbXcQrzK3cyLl0M7gfTm0YWPzaf+d3ATNnq/9j
/952QfmXjVSGhU3EBxlEM6NWstNSNuaTWSMCcbcH+va/AMOHK1rRKQ3IOdzjYcQm
YQIDAQAB
-----END PUBLIC KEY-----
]]
-- END Paths --

-- Helpers --
    local function _hashFile(path)
        local out = hs.execute("shasum -a 256 '" .. path:gsub("'", "'\\'") .. "' 2>/dev/null")

        return (out and #out >= 64) and out:sub(1, 64):lower() or nil
    end

    local function _readTrusted()
        local _paths = { _trustPath, _home .. "/.hammerspoon/.ms_trusted_hash" }

        for _, _p in ipairs(_paths) do
            local f = io.open(_p, "r")

            if f then
                local h = f:read("*all"); f:close()
                h = h and h:match("^%s*([0-9a-fA-F]+)%s*$")

                if h and #h == 64 then return h:lower() end
            end
        end

        return nil
    end

    -- Verify MANIFEST.json RSA-2048 signature.  Returns true only if the
    -- signature is present and validates against the embedded public key.
    -- A missing or empty signature is treated as unverified (returns false)
    -- because unsigned manifests can be forged by anyone with file access.
    local function _verifyManifestSignature(manifest)
        if not manifest.signature or manifest.signature == "" then
            return false  -- unsigned manifest — not trustworthy
        end
        -- The release workflow signs the bundle sha256 (or legacy sha256).
        local signTarget = (manifest.bundle and manifest.bundle.sha256 ~= "")
            and manifest.bundle.sha256 or manifest.sha256
        if not signTarget or signTarget == "" then return false end

        local _keyPath = _dataPath .. "_guardian_pub.pem"
        local _sigPath = _dataPath .. "_guardian_sig.bin"
        local _msgPath = _dataPath .. "_guardian_msg.bin"

        os.execute("mkdir -p '" .. _dataPath .. "'")

        local _kf = io.open(_keyPath, "w")
        if _kf then _kf:write(_publicKey); _kf:close() end

        local _sf = io.open(_sigPath .. ".b64", "w")
        if _sf then _sf:write(manifest.signature); _sf:close() end
        hs.execute("base64 -D -i '" .. _sigPath .. ".b64' -o '" .. _sigPath .. "'")
        os.remove(_sigPath .. ".b64")

        local _mf = io.open(_msgPath, "w")
        if _mf then _mf:write(signTarget:lower()); _mf:close() end

        local _out, _ok = hs.execute(
            "openssl dgst -sha256 -verify '" .. _keyPath ..
            "' -signature '" .. _sigPath ..
            "' '" .. _msgPath .. "' 2>&1"
        )

        os.remove(_keyPath)
        os.remove(_sigPath)
        os.remove(_msgPath)

        return _ok and _out and _out:find("Verified OK") ~= nil
    end
-- END Helpers --

-- Integrity Check --
    local _cur     = _hashFile(_corePath)
    local _trusted = _readTrusted()
    local _blocked = false

    if _cur == nil then
        print("Guardian: could not hash ms_core.lua (shasum unavailable?); skipping check.")

    elseif _trusted and _cur ~= _trusted then
        -- Hash mismatch. Check if MANIFEST.json confirms the current file
        -- is a legitimate update (sha256 matches AND signature is valid).
        -- If so, auto-seed and pass through — no user intervention needed.
        local _manifestOk = false
        do
            local _mPath = _home .. "/.hammerspoon/MANIFEST.json"
            local _mf = io.open(_mPath, "r")
            if _mf then
                local _raw = _mf:read("*all"); _mf:close()
                local _ok, _manifest = pcall(hs.json.decode, _raw)
                if _ok and type(_manifest) == "table"
                    and type(_manifest.sha256) == "string"
                    and #_manifest.sha256 == 64
                    and _manifest.sha256:lower() == _cur:lower()
                    and _verifyManifestSignature(_manifest) then
                    -- MANIFEST confirms the current file is legit and signed. Auto-seed.
                    local _wf = io.open(_trustPath, "w")
                    if _wf then _wf:write(_cur .. "\n"); _wf:close() end
                    _manifestOk = true
                    print("Guardian: hash mismatch but signed MANIFEST.json confirms update — auto-seeded.")
                end
            end
        end

        if not _manifestOk then
        _blocked = true

        pcall(function()
            local _snd = hs.sound.getByFile(_home .. "/.hammerspoon/sounds/Error.wav")

            if _snd then _snd:play() end
        end)

        local _guardianView = nil
        local _guardianPos   = nil -- tracked in Lua, not read back from frame(), to survive drag

        local _ucGuardian = hs.webview.usercontent.new("guardian")

        _ucGuardian:setCallback(function(msg)
            local body = msg.body

            if body == "confirmDelete" then
                pcall(function() if _guardianView then _guardianView:delete() end end)
                os.remove(_trustPath)
                hs.reload()

            elseif body == "keepBlocked" then
                pcall(function() if _guardianView then _guardianView:delete() end end)

            else
                local ok, data = pcall(hs.json.decode, body) -- JSON move delta from the drag handler

                if ok and data and data.action == "move" then
                    pcall(function()
                        if not _guardianPos then return end
                        _guardianPos.x = _guardianPos.x + (data.dx or 0)
                        _guardianPos.y = _guardianPos.y + (data.dy or 0)
                        _guardianView:frame(_guardianPos)
                    end)
                end
            end
        end)

        local _ok, _screen = pcall(function() return hs.screen.mainScreen():frame() end)

        if _ok and _screen then
            local _gw, _gh = 480, 360 -- 4:3

            do
                local _tq = io.open(_home .. "/.hammerspoon/data/ms_theme.json", "r")

                if _tq then
                    local _dq = hs.json.decode(_tq:read("*all")); _tq:close()

                    if type(_dq) == "table" and type(_dq.uifc) == "table"
                        and type(_dq.uifc.guardian) == "string"
                        and _dq.uifc.guardian ~= "" then
                        local _qp = _home .. "/.hammerspoon/"
                            .. (function(p) p=p:gsub("%.%.[/\\]",""):gsub("[/\\]%.%.",""):gsub("^%.%.$",""):gsub("^[/~]+",""); return p end)(_dq.uifc.guardian)

                        if hs.fs.attributes(_qp) then
                            _gw = math.floor(_gw * 1.25)
                            _gh = math.floor(_gh * 1.25)
                        end
                    end
                end
            end

            local _gx = _screen.x + math.floor((_screen.w - _gw) / 2)
            local _gy = _screen.y + math.floor((_screen.h - _gh) / 2)

            _guardianView = hs.webview.new({
                x = _gx,
                y = _gy,
                w = _gw,
                h = _gh,
            }, {}, _ucGuardian)

            _guardianPos = {
                x = _gx,
                y = _gy,
                w = _gw,
                h = _gh,
            }
        end

        if _guardianView then
            pcall(function() _guardianView:windowStyle(0) end)
            pcall(function() _guardianView:level(hs.canvas.windowLevels.popUpMenu or 101) end)
            pcall(function() _guardianView:shadow(true) end)
            pcall(function() _guardianView:allowTextEntry(false) end)

            local _htmlPath = _home .. "/.hammerspoon/ui/ms_guardian.html"
            local _baseURL  = "file://" .. _home .. "/.hammerspoon/ui/"

            local _guardianTheme = nil
            local _guardianUIFC  = nil
            local _tf = io.open(_home .. "/.hammerspoon/data/ms_theme.json", "r")

            if _tf then
                local _td = hs.json.decode(_tf:read("*all")); _tf:close()

                if type(_td) == "table" then
                    _guardianTheme = _td

                    if type(_td.uifc) == "table"
                        and type(_td.uifc.guardian) == "string"
                        and _td.uifc.guardian ~= "" then
                        local _gp = _home .. "/.hammerspoon/"
                            .. (function(p) p=p:gsub("%.%.[/\\]",""):gsub("[/\\]%.%.",""):gsub("^%.%.$",""):gsub("^[/~]+",""); return p end)(_td.uifc.guardian)

                        if hs.fs.attributes(_gp) then
                            _guardianUIFC = "file://" .. _gp
                        end
                    end
                end
            end

            local _gf = io.open(_htmlPath, "r")

            if _gf then
                local _ghtml = _gf:read("*all"); _gf:close()

                _guardianView:html(_ghtml, _baseURL)
                _guardianView:show()

                _guardianView:navigationCallback(function(action)
                    pcall(function()
                        local _t = _trusted:sub(1, 16) .. "\xe2\x80\xa6"
                        local _c = _cur:sub(1, 16)     .. "\xe2\x80\xa6"

                        _guardianView:evaluateJavaScript(
                            "setHashes('" .. _t .. "', '" .. _c .. "')"
                        )

                        if _guardianTheme then
                            local _tj = hs.json.encode(_guardianTheme)

                            if _tj then
                                _guardianView:evaluateJavaScript("applyTheme(" .. _tj .. ")")
                            end
                        end

                        if _guardianUIFC then
                            _guardianView:evaluateJavaScript(
                                "document.body.style.backgroundImage='url(\"" .. _guardianUIFC .. "\")';"
                                .. "document.body.style.backgroundSize='100% 100%';"
                                .. "document.body.style.backgroundRepeat='no-repeat';"
                                .. "document.body.style.padding='12.5%';"
                                .. "document.body.style.boxSizing='border-box';"
                            )
                        end
                    end)
                end)

            else
                _guardianView:delete()
                hs.focus()

                local _choice = hs.dialog.blockAlert(
                    "\xe2\x9a\xa0 ms_core.lua Modified \xe2\x80\x94 mudscript Did Not Load",
                    "Hash mismatch. Delete trusted hash and reload?",
                    "Keep Blocked",
                    "Delete Hash & Reload"
                )

                if _choice == "Delete Hash & Reload" then
                    os.remove(_trustPath); hs.reload()
                end
            end
        else
            hs.focus()

            local _choice = hs.dialog.blockAlert(
                "\xe2\x9a\xa0 ms_core.lua Modified \xe2\x80\x94 mudscript Did Not Load",
                "Hash mismatch. Delete trusted hash and reload?",
                "Keep Blocked",
                "Delete Hash & Reload"
            )

            if _choice == "Delete Hash & Reload" then
                os.remove(_trustPath); hs.reload()
            end
        end
        end -- if not _manifestOk
    end
-- END Integrity Check --

-- Load Core --
    if not _blocked then
        dofile(_corePath)
    end
-- END Load Core --

return _obj