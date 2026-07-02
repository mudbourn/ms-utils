# mudscript

**A macro framework for people who want reliable automation without the sketchy stuff.**

mudscript lets you write, test, and run macros on macOS — with a visual builder, live debugging tools, and a settings panel that actually makes sense. It's built on [Hammerspoon](https://www.hammerspoon.org/), a well-known, open-source automation platform.

> **Windows support is in early development.** The Windows version is not ready for general use — it exists for maintainer testing only. If you're looking for a macro tool on Windows, mudscript is not there yet.

---

## What it does

- **Write macros in plain Lua** (or AHK on Windows) — no proprietary scripting language to learn
- **Visual macro builder** — drag-and-drop steps, inline editors, test-run with one click
- **Live debugging** — console, macro monitor, input monitor, window monitor
- **Profiles** — save, switch, export, and import macro packs
- **Theming** — customize colors, fonts, window radius
- **Sound system** — assign sounds to macro events, import custom audio
- **Settings panel** — everything in one place, no config file editing required

---

## Who it's for

mudscript is for anyone who wants to automate repetitive tasks — whether that's in a game, a creative workflow, or just daily computer use. It's designed to be:

- **Transparent** — you can read every line of code. No obfuscation, no hidden behavior.
- **Safe** — macros run in a sandbox. The tool can't access your files, network, or system without your explicit permission.
- **Maintained** — regular updates, documented API, active development.

---

## Philosophy

I built mudscript to serve the user — not the other way around.

There are a lot of macro tools out there that are either too complicated, too limited, or just plain suspicious. I wanted something that:

1. **Does what it says.** No hidden features, no phone-home, no data collection.
2. **Protects you from bad actors.** The Guardian system verifies that the code you're running is the code I released. If someone tries to modify it and redistribute it as their own, you'll know.
3. **Respects your time.** The visual builder means you don't have to write code if you don't want to. The live tools mean you can see exactly what's happening.
4. **Grows with you.** Start with the visual builder, graduate to writing Lua — the same API supports both.

I'm not interested in building a tool that hides what it does. If you can't understand what a macro tool is doing, you shouldn't trust it.

---

## Getting started

### macOS

```bash
curl -L https://raw.githubusercontent.com/mudbourn/ms-utils/main/mac/install.sh | bash
```

This installs mudscript to `~/.hammerspoon/`, sets up the Guardian, and reloads Hammerspoon. You'll be up and running in under a minute.

**Requirements:** [Hammerspoon](https://www.hammerspoon.org/) (free, open-source)

---

## Keybindings

These work when your target app (Roblox by default) is focused:

| Key | Action |
|---|---|
| `Alt+P` | Open settings / macro builder |
| `Alt+[` | Quick reload |
| `Alt+F10` | Panic — disable all macros |

System hotkeys also work in Hammerspoon, Activity Monitor, and popped-out panels.

---

## Visual macro builder

The macro builder lets you create macros without writing code:

- **Drag and drop** steps to reorder them
- **Nest blocks** — if/else, for loops, while loops
- **Inline editors** — type values, capture keys, pick modifiers
- **Test run** — execute your macro in a sandbox with live feedback
- **Record mode** — capture your inputs and convert them to macro steps

Open it with `Alt+P` → **Macros** tab.

---

## Profiles

Save and switch between macro packs:

- **Save** your current setup (macros, settings, theme)
- **Export** a profile to share with others
- **Import** profiles from `.mspkg` files

Profiles include sounds, themes, and settings — everything you need to switch contexts.

---

## Sound system

Assign sounds to macro events:

- **Built-in slots** — startup, load, alert, hover, interact, and more
- **Custom sounds** — import your own `.wav` files
- **Per-macro sounds** — assign specific sounds to individual macros
- **Volume control** — adjust globally or per-sound

---

## Theming

Customize the look and feel:

- **Colors** — background, surface, accent, text, and more
- **Font** — use any installed font
- **Window radius** — round the corners of all panels
- **Live preview** — changes apply instantly

Edit `data/ms_theme.json` or use the Settings panel.

---

## Updates

mudscript checks for updates automatically:

- **Stable channel** — tested releases with signed manifests
- **Testing channel** — latest builds from the development branch

Switch channels from Settings → Developer → Update Channel.

---

## What mudscript is NOT

- **Not a cheat tool.** mudscript is a macro framework. What you do with it is your responsibility.
- **Not malware.** Every line of code is readable. The Guardian system protects *you* from tampered versions, not the other way around.
- **Not a data collector.** mudscript doesn't phone home, doesn't track you, and doesn't send anything anywhere.
- **Not a black box.** If you want to understand how it works, read the code. It's all there.

---

## Documentation

- **[macOS API Reference](docs/DOCS_MAC.md)** — every `ms.*` function documented
- **[Windows API Reference](docs/DOCS_WINDOWS.md)** — Windows-specific API
- **[Function Index](docs/function-index.md)** — quick reference for all functions
- **[Icon Requirements](docs/icon-requirements.md)** — SVG icon specifications
- **[Architecture](docs/ARCHITECTURE.md)** — technical details, directory layout, security model

---

## Contributing

mudscript is open-source under the [MIT License](LICENSE). Contributions are welcome:

- **Bug reports** — open an issue with steps to reproduce
- **Feature requests** — describe what you want and why
- **Code** — fork, branch, PR
- **Documentation** — help improve the docs
- **Macro packs** — share your profiles and macros

---

## License

[MIT License](LICENSE) — use it however you want.

---

## Credits

Built with [Hammerspoon](https://www.hammerspoon.org/) and [AutoHotkey](https://www.autohotkey.com/).

Icons from [Lucide](https://lucide.dev/) and [SVG Repo](https://www.svgrepo.com/).
