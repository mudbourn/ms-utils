(function() {
"use strict";
  // Styles //
      const SELECT_CSS = `
        .macro-select { position: relative; display: flex; align-items: center; gap: 6px; background: var(--surface2); border: 1px solid var(--border-dim); border-radius: var(--radius); color: var(--text); font-size: 11px; padding: 4px 8px; outline: none; font-family: inherit; cursor: pointer; min-width: 120px; }
        .macro-select:hover { border-color: var(--border); }
        .macro-select:focus, .macro-select.open { border-color: var(--accent); }
        .macro-select-label { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .macro-select-arrow { display: flex; align-items: center; font-size: 8px; color: var(--text3); flex-shrink: 0; }
        .macro-select-arrow .icon { width: 12px; height: 12px; }
        .macro-select-menu { display: none; position: absolute; top: calc(100% + 3px); left: 0; min-width: 100%; max-height: 260px; overflow-y: auto; background: var(--surface2); border: 1px solid var(--border); border-radius: var(--radius); z-index: 100; box-shadow: 0 4px 16px rgba(0,0,0,0.5); }
        .macro-select.open .macro-select-menu { display: block; }
        .macro-select-item { padding: 5px 10px; font-size: 11px; color: var(--text2); white-space: nowrap; cursor: pointer; transition: background 0.12s, color 0.12s; }
        .macro-select-item:hover { background: var(--hover); color: var(--text); }
        .macro-select-item.active { color: var(--accent); }
        .macro-select-menu::-webkit-scrollbar { width: 4px; }
        .macro-select-menu::-webkit-scrollbar-track { background: transparent; }
        .macro-select-menu::-webkit-scrollbar-thumb { background: var(--border-dim); border-radius: 2px; }
        `;

      function injectSelectStyles(doc) {
          doc = doc || document;
          if (doc.getElementById("ui-select-css")) return;
          const style = doc.createElement("style");
          style.id = "ui-select-css";
          style.textContent = SELECT_CSS;
          (doc.head || doc.documentElement).appendChild(style);
      }
  // END Styles //

  // Factory //
      function createSelect(opts) {
          opts = opts || {};
          injectSelectStyles(opts.doc);

          const doc = opts.doc || document;
          const root = doc.createElement("div");
          root.className = "macro-select" + (opts.className ? " " + opts.className : "");
          root.tabIndex = 0;
          if (opts.minWidth) root.style.minWidth = opts.minWidth + "px";

          const label = doc.createElement("span");
          label.className = "macro-select-label";
          root.appendChild(label);

          const arrow = doc.createElement("span");
          arrow.className = "macro-select-arrow";
          if (window.ICONS && window.ICONS.chevdown && typeof window.icon === "function") {
              arrow.innerHTML = window.icon("chevdown");
          } else {
              arrow.textContent = "▾";
          }
          root.appendChild(arrow);

          const menu = doc.createElement("div");
          menu.className = "macro-select-menu";
          root.appendChild(menu);

          let _opts = [];
          let _value = "";

          function play(slot) { if (window.playSlot) window.playSlot(slot); }

          function normalise(list) {
              return (list || []).map((o) =>
                  (o && typeof o === "object")
                      ? { value: String(o.value), label: String(o.label == null ? o.value : o.label) }
                      : { value: String(o), label: String(o) }
              );
          }

          function labelFor(v) {
              for (const o of _opts) if (o.value === v) return o.label;
              return _opts.length ? _opts[0].label : (opts.placeholder || "");
          }

          function close() {
              root.classList.remove("open");
              menu.style.position = "";
              menu.style.left = "";
              menu.style.top = "";
              menu.style.bottom = "";
              menu.style.minWidth = "";
              menu.style.maxHeight = "";
          }

          function place() {
              const r   = root.getBoundingClientRect();
              const vh  = doc.documentElement.clientHeight;
              const gap = 3;
              const below = vh - r.bottom - gap;
              const above = r.top - gap;
              const flip  = below < Math.min(260, menu.scrollHeight) && above > below;

              menu.style.position = "fixed";
              menu.style.left     = r.left + "px";
              menu.style.minWidth = r.width + "px";
              menu.style.maxHeight = Math.max(80, Math.min(260, flip ? above : below)) + "px";
              if (flip) {
                  menu.style.top    = "auto";
                  menu.style.bottom = (vh - r.top + gap) + "px";
              } else {
                  menu.style.bottom = "auto";
                  menu.style.top    = (r.bottom + gap) + "px";
              }
          }

          function render() {
              label.textContent = labelFor(_value);
              menu.innerHTML = "";
              _opts.forEach((o) => {
                  const item = doc.createElement("div");
                  item.className = "macro-select-item" + (o.value === _value ? " active" : "");
                  item.textContent = o.label;
                  item.addEventListener("mouseenter", () => play("hover"));
                  item.addEventListener("click", (e) => {
                      e.stopPropagation();
                      play("interact");
                      close();
                      if (o.value === _value) return;
                      _value = o.value;
                      render();
                      if (opts.onChange) opts.onChange(_value);
                      root.dispatchEvent(new Event("change"));
                  });
                  menu.appendChild(item);
              });
          }

          root.setOptions = function(list) {
              _opts = normalise(list);
              if (!_opts.some((o) => o.value === _value)) {
                  _value = _opts.length ? _opts[0].value : "";
              }
              render();
          };

          Object.defineProperty(root, "value", {
              get: () => _value,
              set: (v) => { _value = v == null ? "" : String(v); render(); },
          });

          Object.defineProperty(root, "options", { get: () => _opts.slice() });

          root.addEventListener("mouseenter", () => play("hover"));
          root.addEventListener("click", (e) => {
              e.stopPropagation();
              if (root.classList.contains("open")) { close(); return; }
              play("interact");
              root.classList.add("open");
              place();
          });
          doc.addEventListener("scroll", function(e) {
              if (menu.contains(e.target)) return;
              close();
          }, true);
          window.addEventListener("resize", close);
          root.addEventListener("keydown", (e) => {
              if (e.key === "Escape") close();
              e.stopPropagation();
          });
          doc.addEventListener("click", close);

          root.setOptions(opts.options || []);
          if (opts.value !== undefined && opts.value !== null) root.value = opts.value;
          else if (!_opts.length && opts.placeholder) label.textContent = opts.placeholder;

          return root;
      }
  // END Factory //

  // Exports //
      window.createSelect       = createSelect;
      window.injectSelectStyles = injectSelectStyles;
      window.SELECT_CSS         = SELECT_CSS;
  // END Exports //
})();
