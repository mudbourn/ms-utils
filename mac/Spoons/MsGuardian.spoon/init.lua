-- mudscript pre-load integrity check — see DOCS_MAC.md § 20 for the full security model.

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
        local out = hs.execute("shasum -a 256 '" .. path:gsub("'", "'\\''") .. "' 2>/dev/null")

        return (out and #out >= 64) and out:sub(1, 64):lower() or nil
    end

    -- Returns: table {relativePath = hash64} or nil
    -- Handles both old single-hash format and new JSON manifest format
    local function _readTrustedManifest()
        local _paths = { _trustPath, _home .. "/.hammerspoon/.ms_trusted_hash" }

        for _, _p in ipairs(_paths) do
            local f = io.open(_p, "r")
            if f then
                local raw = f:read("*all"); f:close()
                if raw and raw ~= "" then
                    -- Old format: single hex hash
                    local single = raw:match("^%s*([0-9a-fA-F]+)%s*$")
                    if single and #single == 64 then
                        return { ["ms_core.lua"] = single:lower() }
                    end
                    -- New format: JSON manifest
                    local ok, tbl = pcall(hs.json.decode, raw)
                    if ok and type(tbl) == "table" then
                        local norm = {}
                        for k, v in pairs(tbl) do
                            if type(v) == "string" and #v == 64 then
                                local rel = k:gsub(".*/%.hammerspoon/", "")
                                norm[rel] = v:lower()
                            end
                        end
                        if next(norm) then return norm end
                    end
                end
            end
        end

        return nil
    end

    -- Backward compat: returns ms_core.lua hash
    local function _readTrusted()
        local m = _readTrustedManifest()
        return m and m["ms_core.lua"] or nil
    end

    -- Discover all spoon init files
    local function _trackedFiles()
        local files = { _corePath }
        local spoonDir = _home .. "/.hammerspoon/Spoons/"
        local ok, iter, dir_obj = pcall(hs.fs.dir, spoonDir)
        if ok and iter then
            for entry in iter, dir_obj do
                if entry ~= "." and entry ~= ".." then
                    local init = spoonDir .. entry .. "/init.lua"
                    if hs.fs.attributes(init) then
                        files[#files + 1] = init
                    end
                end
            end
            dir_obj:close()
        end
        table.sort(files)
        return files
    end

    -- Check all files against manifest. Returns: "ok", "mismatch", "uninitialized"
    -- On mismatch, returns second value = filename that failed
    local function _checkAll(manifest)
        if not manifest then return "uninitialized" end
        local files = _trackedFiles()
        for _, absPath in ipairs(files) do
            local rel = absPath:gsub(".*/%.hammerspoon/", "")
            local expected = manifest[rel]
            if expected then
                local cur = _hashFile(absPath)
                if not cur then return "error", rel end
                if cur ~= expected then return "mismatch", rel end
            end
        end
        return "ok"
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

    -- Read per-file integrity manifest (from CI). Returns parsed table or nil.
    local function _readFileManifest()
        local _fmPath = _home .. "/.hammerspoon/data/.ms_file_manifest.json"
        local f = io.open(_fmPath, "r")
        if not f then return nil end
        local raw = f:read("*all"); f:close()
        if not raw or raw == "" then return nil end
        local ok, tbl = pcall(hs.json.decode, raw)
        if ok and type(tbl) == "table" and type(tbl.files) == "table" then
            return tbl
        end
        return nil
    end

    -- Verify per-file manifest RSA-2048 signature.  Returns true only if the
    -- signature is present and validates against the embedded public key.
    local function _verifyFileManifestSignature(fm)
        if not fm.signature or fm.signature == "" then
            return false
        end

        -- Build minified JSON of just {version, generated, files} matching what CI signs.
        -- MUST use jq -c -S to guarantee sorted keys (matching CI's jq -c output).
        -- hs.json.encode does not sort keys and would produce a different payload.
        local signPayload = { version = fm.version, generated = fm.generated, files = fm.files }
        local okEncode, unsorted = pcall(hs.json.encode, signPayload)
        if not okEncode or not unsorted then return false end

        local _sortTmp = _dataPath .. "_guardian_sort_tmp.json"
        local _stf = io.open(_sortTmp, "w")
        if _stf then _stf:write(unsorted); _stf:close() end
        local sortedOut = hs.execute("jq -c -S '.' '" .. _sortTmp .. "' 2>/dev/null")
        os.remove(_sortTmp)
        local minified = sortedOut and sortedOut ~= "" and sortedOut:sub(-1) == "\n"
            and sortedOut:sub(1, -2) or sortedOut
        if not minified or minified == "" then return false end

        local _keyPath = _dataPath .. "_guardian_pub.pem"
        local _sigPath = _dataPath .. "_guardian_sig.bin"
        local _msgPath = _dataPath .. "_guardian_msg.bin"

        os.execute("mkdir -p '" .. _dataPath .. "'")

        local _kf = io.open(_keyPath, "w")
        if _kf then _kf:write(_publicKey); _kf:close() end

        local _sf = io.open(_sigPath .. ".b64", "w")
        if _sf then _sf:write(fm.signature); _sf:close() end
        hs.execute("base64 -D -i '" .. _sigPath .. ".b64' -o '" .. _sigPath .. "'")
        os.remove(_sigPath .. ".b64")

        -- Write the minified JSON as the message (CI signs the JSON directly, not a hash)
        local _mf = io.open(_msgPath, "w")
        if _mf then _mf:write(minified); _mf:close() end

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

    -- Check per-file manifest integrity.
    -- Returns: 'ok', 'legacy', 'tampered', or 'mismatch' + filename
    local function _checkFileManifest()
        local fm = _readFileManifest()
        if not fm then return "legacy" end

        if not _verifyFileManifestSignature(fm) then
            return "tampered"
        end

        for relPath, expected in pairs(fm.files) do
            if type(expected) == "string" and #expected == 64 then
                local absPath = _home .. "/.hammerspoon/" .. relPath
                if hs.fs.attributes(absPath) then
                    local cur = _hashFile(absPath)
                    if not cur then return "mismatch", relPath end
                    if cur ~= expected:lower() then return "mismatch", relPath end
                end
            end
        end

        return "ok"
    end

    -- Show the Guardian blocking UI (webview or dialog fallback).
    -- Called when integrity check fails and we need to block loading.
    local function _showGuardianBlock()
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
                        local _t = (_trusted or "unknown"):sub(1, 16) .. "\xe2\x80\xa6"
                        local _c = (_cur or "unknown"):sub(1, 16)     .. "\xe2\x80\xa6"

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
                    "\u{26a0} Integrity Error \u{2014} mudscript Did Not Load",
                    "File hash mismatch detected. Delete trusted manifest and reload?",
                    "Keep Blocked",
                    "Delete Manifest & Reload"
                )

                if _choice == "Delete Manifest & Reload" then
                    os.remove(_trustPath); hs.reload()
                end
            end
        else
            hs.focus()

            local _choice = hs.dialog.blockAlert(
                "\u{26a0} Integrity Error \u{2014} mudscript Did Not Load",
                "File hash mismatch detected. Delete trusted manifest and reload?",
                "Keep Blocked",
                "Delete Manifest & Reload"
            )

            if _choice == "Delete Manifest & Reload" then
                os.remove(_trustPath); hs.reload()
            end
        end
    end
-- END Helpers --

-- Integrity Check --
    local _blocked = false
    local _manifest = _readTrustedManifest()
    local _fmResult, _fmFailedFile = _checkFileManifest()

    if _fmResult == "ok" then
        -- Per-file manifest passed — all files verified via signed manifest
        print("Guardian: per-file manifest verified — all files intact.")
        -- Also write the old trusted hash format so ms.integrity.check() sees "trusted"
        pcall(function()
            local fm = _readFileManifest()
            if fm and fm.files then
                local ok, json = pcall(hs.json.encode, fm.files)
                if ok then
                    local wf = io.open(_trustPath, "w")
                    if wf then wf:write(json .. "\n"); wf:close() end
                end
            end
        end)

    elseif _fmResult == "legacy" then
        -- No per-file manifest — fall back to old single-hash / JSON behavior
        local _checkResult, _failedFile = _checkAll(_manifest)

        if _checkResult == "uninitialized" then
            print("Guardian: no trusted manifest — skipping check.")

        elseif _checkResult == "error" then
            print("Guardian: could not hash " .. (_failedFile or "unknown") .. "; skipping check.")

        elseif _checkResult == "mismatch" then
            local _manifestOk = false
            do
                local _cur = _hashFile(_corePath)
                local _mPath = _home .. "/.hammerspoon/MANIFEST.json"
                local _mf = io.open(_mPath, "r")
                if _mf and _cur then
                    local _raw = _mf:read("*all"); _mf:close()
                    local _ok, _m = pcall(hs.json.decode, _raw)
                    if _ok and type(_m) == "table"
                        and type(_m.sha256) == "string"
                        and #_m.sha256 == 64
                        and _m.sha256:lower() == _cur:lower()
                        and _verifyManifestSignature(_m) then
                        -- Re-seed old manifest
                        local files = _trackedFiles()
                        local newManifest = {}
                        for _, absPath in ipairs(files) do
                            local h = _hashFile(absPath)
                            if h then
                                local rel = absPath:gsub(".*/%.hammerspoon/", "")
                                newManifest[rel] = h
                            end
                        end
                        local ok2, json = pcall(hs.json.encode, newManifest)
                        if ok2 then
                            local _wf = io.open(_trustPath, "w")
                            if _wf then _wf:write(json .. "\n"); _wf:close() end
                        end
                        _manifestOk = true
                        print("Guardian: hash mismatch but signed MANIFEST.json confirms update — auto-seeded all files.")
                    end
                end
            end

            if not _manifestOk then
                _blocked = true
                _showGuardianBlock()
            end
        end -- if _checkResult
    elseif _fmResult == "tampered" then
        -- Per-file manifest itself is suspect — block immediately
        _blocked = true
        _showGuardianBlock()
        print("Guardian: per-file manifest signature verification failed — blocking.")

    elseif _fmResult == "mismatch" then
        -- Per-file hash mismatch. Check if MANIFEST.json confirms a legit update.
        local _manifestOk = false
        do
            local _cur = _hashFile(_corePath)
            local _mPath = _home .. "/.hammerspoon/MANIFEST.json"
            local _mf = io.open(_mPath, "r")
            if _mf and _cur then
                local _raw = _mf:read("*all"); _mf:close()
                local _ok, _m = pcall(hs.json.decode, _raw)
                if _ok and type(_m) == "table"
                    and type(_m.sha256) == "string"
                    and #_m.sha256 == 64
                    and _m.sha256:lower() == _cur:lower()
                    and _verifyManifestSignature(_m) then
                    -- MANIFEST confirms the current file is legit and signed.
                    -- Re-seed both per-file manifest (unsigned) and old trusted hash.
                    local fm = _readFileManifest()
                    local tracked = fm and fm.files or {}
                    local files = _trackedFiles()
                    local newFM = { version = "", generated = os.date("!%Y-%m-%dT%H:%M:%SZ"), files = {}, signature = "" }

                    if fm and fm.version then newFM.version = fm.version end
                    if fm and fm.signature then newFM.signature = fm.signature end

                    -- Hash all files from per-file manifest scope
                    for relPath, _ in pairs(tracked) do
                        local absPath = _home .. "/.hammerspoon/" .. relPath
                        local h = _hashFile(absPath)
                        if h then newFM.files[relPath] = h end
                    end

                    -- Also hash tracked files (spoons + core) not already covered
                    local oldManifest = {}
                    for _, absPath in ipairs(files) do
                        local h = _hashFile(absPath)
                        if h then
                            local rel = absPath:gsub(".*/%.hammerspoon/", "")
                            oldManifest[rel] = h
                            if not newFM.files[rel] then newFM.files[rel] = h end
                        end
                    end

                    -- Write old trusted hash for backward compat
                    local okOld, jsonOld = pcall(hs.json.encode, oldManifest)
                    if okOld then
                        local _wf = io.open(_trustPath, "w")
                        if _wf then _wf:write(jsonOld .. "\n"); _wf:close() end
                    end

                    _manifestOk = true
                    print("Guardian: per-file mismatch but signed MANIFEST.json confirms update — auto-seeded trusted manifest.")
                end
            end
        end

        if not _manifestOk then
            _blocked = true
            _showGuardianBlock()
            print("Guardian: per-file hash mismatch for " .. (_fmFailedFile or "unknown") .. " — blocking.")
        end
    end
-- END Integrity Check --

-- Set guardian tether flag — all spoons check for this
    if not _blocked then
        _G._guardianPassed = true
    end

-- Load Core --
    if not _blocked then
        dofile(_corePath)
    end
-- END Load Core --

return _obj