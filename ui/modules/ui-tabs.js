    (function() {
    "use strict";

    /* ── ui-tabs.js ────────────────────────────────────────────────────── */
/**
 * createTabs — shared tab-strip factory for mudscript panels.
 *
 * Every tabbed surface had its own copy of the same switchTab(): toggle
 * .active on the buttons, toggle .active on the sections, then do one
 * panel-specific thing afterwards. This is that, once.
 *
 * Tabs are for *expansion* — a panel grows new surface. They are not for
 * chopping a panel's existing content into pieces.
 *
 * Usage:
 *
 *   const tabs = createTabs({
 *     root: panelEl,                       // scope; defaults to document
 *     tabKey:     (el) => el.dataset.wtab, // defaults to id "tab-<key>"
 *     sectionKey: (el) => el.dataset.wsection,
 *     onSwitch(tab, prev) { ... },         // after the classes are applied
 *     onSame(tab) { playSlot("back"); },   // clicked the tab already showing
 *   });
 *
 *   window.switchTab = tabs.switch;
 *
 * The two key functions must agree on the same vocabulary of tab names —
 * a button and its section are paired by the string they both return.
 */

// ── Styles ───────────────────────────────────────────────────────────────
// The canonical tab CSS. Themed surfaces pull their colours from the same
// CSS variables the rest of the UI uses, so this travels with the module
// rather than being retyped per page.
const TABS_CSS = `
#tabs { display: flex; background: var(--surface); border-bottom: 1px solid var(--border); flex-shrink: 0; }
.tab {
    flex: 1; padding: 7px 12px; font-size: 12px; font-weight: 600; color: var(--text2);
    text-align: center; cursor: pointer; background: none;
    border: none; border-bottom: 2px solid transparent;
    transition: color 0.15s, border-color 0.15s; -webkit-app-region: no-drag;
}
.tab:hover { color: var(--text); }
.tab.active { color: var(--accent); border-bottom-color: var(--accent); }
.tab-section { display: none; flex-direction: column; flex: 1; overflow: hidden; }
.tab-section.active { display: flex; }
`;

// Idempotent — safe to call from every panel that uses tabs.
function injectTabStyles(doc) {
    doc = doc || document;
    if (doc.getElementById("ui-tabs-css")) return;
    const style = doc.createElement("style");
    style.id = "ui-tabs-css";
    style.textContent = TABS_CSS;
    (doc.head || doc.documentElement).appendChild(style);
}

// ── Factory ──────────────────────────────────────────────────────────────
function createTabs(opts) {
    opts = opts || {};

    const root            = opts.root || document;
    const tabSelector     = opts.tabSelector || ".tab";
    const sectionSelector = opts.sectionSelector || ".tab-section";

    // Default vocabulary: <button id="tab-foo"> pairs with <div id="foo-section">.
    const tabKey = opts.tabKey || ((el) => (el.id || "").replace(/^tab-/, ""));
    const sectionKey = opts.sectionKey
        || ((el) => (el.id || "").replace(/-section$/, ""));

    const onSwitch = typeof opts.onSwitch === "function" ? opts.onSwitch : null;
    const onSame   = typeof opts.onSame   === "function" ? opts.onSame   : null;

    function tabEls()     { return Array.from(root.querySelectorAll(tabSelector)); }
    function sectionEls() { return Array.from(root.querySelectorAll(sectionSelector)); }

    function active() {
        const el = tabEls().find((t) => t.classList.contains("active"));
        return el ? tabKey(el) : null;
    }

    function apply(tab) {
        tabEls().forEach((t) => t.classList.toggle("active", tabKey(t) === tab));
        sectionEls().forEach((s) => s.classList.toggle("active", sectionKey(s) === tab));
    }

    function switchTo(tab) {
        const prev = active();
        if (prev === tab) {
            if (onSame) onSame(tab);
            return;
        }
        apply(tab);
        if (onSwitch) onSwitch(tab, prev);
    }

    if (opts.initial) apply(opts.initial);

    return {
        switch: switchTo,
        active,
        // Re-assert the current tab after markup is rebuilt underneath it.
        refresh: () => { const a = active(); if (a) apply(a); },
    };
}

    window.createTabs      = createTabs;
    window.injectTabStyles = injectTabStyles;
    window.TABS_CSS        = TABS_CSS;

    })();
