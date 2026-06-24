# lib/

Required libraries for the Windows version of ms-utils.

## Quick install

Run this from the project root — it downloads everything automatically:

```batch
bin\install_deps.bat
```

This also generates a tray icon (`ui/icons/ms_icon.ico`) from the source `.tiff` files.

## Manual install

Place the following files here if you prefer to download manually:

| File | Source | Notes |
|---|---|---|
| `WebView2.ahk` | [thqby/ahk2_lib](https://github.com/thqby/ahk2_lib/tree/master/WebView2) | Download `WebView2.ahk` and its companion `WebView2/` folder |
| `Jxon.ahk` | [TheArkive/JXON_ahk2](https://github.com/TheArkive/JXON_ahk2) | Download `Jxon.ahk` |

Both are required by `ms_core.ahk` and `init.ahk`.
WebView2 Runtime must also be installed (pre-installed on Windows 10 21H2+ and all Windows 11).
