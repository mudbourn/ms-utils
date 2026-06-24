# lib/

Required libraries for the Windows version of ms-utils.

## Quick install

Run this from the project root — it downloads everything automatically:

```batch
bin\install_deps.bat
```

This also generates a tray icon (`ui/icons/ms_icon.png`) from the source `.tiff` files.

## Files

| File | Source | Notes |
|---|---|---|
| `WebView2.ahk` | [thqby/ahk2_lib](https://github.com/thqby/ahk2_lib) | WebView2 control wrapper |
| `ComVar.ahk` | [thqby/ahk2_lib](https://github.com/thqby/ahk2_lib) | Required by WebView2.ahk |
| `Promise.ahk` | [thqby/ahk2_lib](https://github.com/thqby/ahk2_lib) | Required by WebView2.ahk |
| `WebView2/` | [thqby/ahk2_lib](https://github.com/thqby/ahk2_lib) | Companion folder (WebView2Loader DLLs) |
| `Jxon.ahk` | [TheArkive/JXON_ahk2](https://github.com/TheArkive/JXON_ahk2) | JSON serializer/deserializer |

All are MIT-licensed open source libraries.

WebView2 Runtime must also be installed (pre-installed on Windows 10 21H2+ and all Windows 11).
