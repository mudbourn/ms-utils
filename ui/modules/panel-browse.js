    /* panel: browse */
    (function() {
    "use strict";

    /* ── panel-browse.js ────────────────────────────────────────────────────
     *
     * The Browse stage: the one universal storefront for the validated
     * library. Every package type — profile, plugin, theme, sound, macro —
     * is discovered and installed here, and here only. Management stays with
     * each type's own panel (a plugin toggles in Plugins, a theme applies in
     * Theme); this stage never manages, it only finds and installs.
     *
     * Trust comes off the registry entry and nowhere else: an entry is in the
     * signed index or it is not. We render the badge the entry carries and
     * hand the install to ms.package, which re-checks trust before it writes.
     *
     * Data is fetched lazily — the catalog is a network document with a TTL,
     * so we ask for it the first time the stage is opened rather than folding
     * it into the settings state that every panel repaint carries. Lua answers
     * 'browseList' with a 'catalog' push; a manual Refresh forces a refetch.
     *
     * Building blocks come from window.msUI (panel-settings.js), same as the
     * other module panels. This panel owns only its cards and toolbar.
     */

    // ── State ────────────────────────────────────────────────────────────
    let S = {
        entries:    null,   // null = never loaded; [] = loaded, empty
        loading:    false,
        error:      null,
        query:      "",
        type:       "all",
        loadedOnce: false,
    };

    function ui() { return window.msUI || null; }
    function playSlot(slot) { if (window.playSlot) window.playSlot(slot); }

    // Actions ride the browse channel so they read as browse actions in the
    // log; ms_ui.lua routes ui:browse:* into the same handler set.
    function send(action, body) {
        if (!window.shellPost) return;
        window.shellPost("browse", action, Object.assign({ action }, body || {}));
    }

    const TYPES = [
        { value: "all",     label: "All" },
        { value: "profile", label: "Profiles" },
        { value: "plugin",  label: "Plugins" },
        { value: "theme",   label: "Themes" },
        { value: "sound",   label: "Sounds" },
        { value: "macro",   label: "Macros" },
    ];

    const TRUST = {
        trusted:   { pill: "",       label: "Trusted" },
        community: { pill: "danger", label: "Community" },
    };

    // ── Data ─────────────────────────────────────────────────────────────
    function requestCatalog(opts) {
        S.loading = true;
        S.error   = null;
        render();
        send("browseList", Object.assign({ query: S.query, type: S.type }, opts || {}));
    }

    // Called by the rail button the first time this stage is shown.
    function ensureLoaded() {
        if (S.loadedOnce) return;
        S.loadedOnce = true;
        requestCatalog();
    }

    // ── Filtering ────────────────────────────────────────────────────────
    // Lua already filters, but re-filtering here keeps typing responsive
    // without a round-trip per keystroke: we narrow the last catalog locally
    // and only refetch on Refresh.
    function visible() {
        const all = Array.isArray(S.entries) ? S.entries : [];
        const q = S.query.trim().toLowerCase();
        return all.filter((e) => {
            if (S.type !== "all" && e.type !== S.type) return false;
            if (!q) return true;
            return (e.name || "").toLowerCase().includes(q)
                || (e.author || "").toLowerCase().includes(q)
                || (e.description || "").toLowerCase().includes(q);
        });
    }

    // ── Card ─────────────────────────────────────────────────────────────
    function packageCard(e) {
        const { h, actionBtn } = ui();
        const card = h("div", {
            cls: "browse-card",
            onmouseenter: () => playSlot("hover"),
        });

        const name = h("div", { cls: "browse-name" }, e.name || e.id);
        const t = TRUST[e.trust] || TRUST.community;
        name.appendChild(h("span", { cls: "pill " + t.pill }, t.label));

        const bits = [];
        const typeLabel = (TYPES.find((x) => x.value === e.type) || {}).label
            || e.type;
        bits.push(String(typeLabel).replace(/s$/, "")); // "Themes" → "Theme"
        if (e.version) bits.push("v" + e.version);
        if (e.author)  bits.push("by " + e.author);

        const id = h("div", { cls: "browse-card-id" },
            name,
            h("div", { cls: "browse-meta", title: bits.join("  ·  ") },
                bits.join("  ·  ")),
        );
        card.appendChild(h("div", { cls: "browse-card-top" }, id));

        if (e.description) {
            card.appendChild(h("div", { cls: "browse-desc" }, e.description));
        }

        const actions = h("div", { cls: "browse-actions" });
        actions.appendChild(actionBtn("Install", "accent", () =>
            send("browseInstall", { id: e.id, label: e.name || e.id })));
        if (e.website) {
            actions.appendChild(actionBtn("Website", "", () =>
                send("openURL", { url: e.website })));
        }
        card.appendChild(actions);

        return card;
    }

    // ── Toolbar ──────────────────────────────────────────────────────────
    function toolbar() {
        const { h, seg, actionBtn } = ui();
        const bar = h("div", { cls: "browse-toolbar" });

        const search = h("input", {
            cls: "browse-search",
            type: "text",
            placeholder: "Search the library…",
            value: S.query,
            oninput: (ev) => { S.query = ev.target.value; renderResults(); },
        });
        bar.appendChild(search);

        bar.appendChild(seg(TYPES, S.type, (v) => { S.type = v; renderResults(); }));

        bar.appendChild(actionBtn("Refresh", "", () => {
            playSlot("interact");
            requestCatalog({ force: true });
        }));

        return bar;
    }

    // ── Results region ───────────────────────────────────────────────────
    function results() {
        const { h, groupLabel } = ui();
        const wrap = h("div", { cls: "browse-results" });

        if (S.loading && S.entries === null) {
            wrap.appendChild(h("div", { cls: "browse-empty" }, "Loading the library…"));
            return wrap;
        }
        if (S.error) {
            wrap.appendChild(h("div", { cls: "browse-empty" },
                h("div", {}, "Could not load the library."),
                h("div", { cls: "browse-empty-sub" }, S.error),
            ));
            return wrap;
        }

        const list = visible();
        if (list.length === 0) {
            const catalogEmpty = !Array.isArray(S.entries) || S.entries.length === 0;
            wrap.appendChild(h("div", { cls: "browse-empty" },
                h("div", {}, catalogEmpty
                    ? "The library has no packages yet."
                    : "No packages match your search."),
                h("div", { cls: "browse-empty-sub" }, catalogEmpty
                    ? "New profiles, plugins, themes, sounds and macros show up "
                    + "here once they are published to the validated library."
                    : "Try a different search or type filter."),
            ));
            return wrap;
        }

        // Group by type when browsing everything; a flat list otherwise.
        if (S.type === "all") {
            for (const t of TYPES) {
                if (t.value === "all") continue;
                const group = list.filter((e) => e.type === t.value);
                if (group.length === 0) continue;
                wrap.appendChild(groupLabel(t.label));
                for (const e of group) wrap.appendChild(packageCard(e));
            }
        } else {
            for (const e of list) wrap.appendChild(packageCard(e));
        }
        return wrap;
    }

    // ── Style ────────────────────────────────────────────────────────────
    // Self-contained so the panel reads correctly before any theme-specific
    // card CSS exists for it. Uses theme tokens only.
    function ensureStyle() {
        if (document.getElementById("browse-style")) return;
        const css = `
        #browse-root { display:flex; flex-direction:column; gap:0; }
        .browse-toolbar { display:flex; gap:8px; align-items:center;
            padding:10px 14px; position:sticky; top:0; z-index:2;
            background:var(--bg); border-bottom:1px solid var(--border-dim); }
        .browse-search { flex:1 1 auto; min-width:0; padding:6px 10px;
            border:1px solid var(--border); border-radius:var(--radius-s);
            background:var(--surface); color:var(--text);
            font-family:inherit; font-size:13px; outline:none; }
        .browse-search:focus { border-color:var(--accent); }
        .browse-results { display:flex; flex-direction:column; gap:8px;
            padding:12px 14px; }
        .browse-card { border:1px solid var(--border-dim);
            border-radius:var(--radius); background:var(--surface);
            padding:10px 12px; display:flex; flex-direction:column; gap:8px; }
        .browse-card-top { display:flex; justify-content:space-between;
            align-items:flex-start; gap:8px; }
        .browse-name { font-weight:600; color:var(--text);
            display:flex; align-items:center; gap:8px; flex-wrap:wrap; }
        .browse-meta { color:var(--text3); font-size:11px; margin-top:3px; }
        .browse-desc { color:var(--text2); font-size:12px; line-height:1.45; }
        .browse-actions { display:flex; gap:8px; }
        .browse-empty { padding:40px 16px; text-align:center;
            color:var(--text2); }
        .browse-empty-sub { margin-top:8px; color:var(--text3);
            font-size:12px; line-height:1.5; max-width:34ch;
            margin-left:auto; margin-right:auto; }
        `;
        const el = document.createElement("style");
        el.id = "browse-style";
        el.textContent = css;
        document.head.appendChild(el);
    }

    // ── Render ───────────────────────────────────────────────────────────
    // Two seams: render() rebuilds the whole panel (toolbar + results);
    // renderResults() repaints only the list, so typing in the search box
    // never steals focus from the input.
    function render() {
        if (!ui()) return;
        const root = document.getElementById("browse-root");
        if (!root) return;
        ensureStyle();
        root.innerHTML = "";
        root.appendChild(toolbar());
        const box = document.createElement("div");
        box.id = "browse-results-box";
        box.appendChild(results());
        root.appendChild(box);
    }

    function renderResults() {
        if (!ui()) return;
        const box = document.getElementById("browse-results-box");
        if (!box) { render(); return; }
        box.innerHTML = "";
        box.appendChild(results());
    }

    // ── Bridge ───────────────────────────────────────────────────────────
    if (window.registerPanel) {
        window.registerPanel("browse", function(action, body) {
            if (action === "catalog") {
                S.entries = Array.isArray(body && body.entries) ? body.entries : [];
                S.loading = false;
                S.error   = (body && body.error) || null;
                render();
            } else if (action === "error") {
                S.loading = false;
                S.error   = (body && body.message) || "Unknown error.";
                render();
            }
        });
    }

    // Lazy first load: fetch the catalog the first time the stage is opened,
    // not at boot — the registry is a network document and most sessions
    // never open Browse.
    const railBtn = document.querySelector('.rail-item[data-panel="browse"]');
    if (railBtn) railBtn.addEventListener("click", ensureLoaded);

    window.renderBrowsePanel = render;

    })();
