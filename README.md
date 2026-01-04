# PICO-8 for Android
*todo: write a proper readme*

## whats this stuff
- `frontend/`: Godot app part; sets up environment and handles video output and keyboard/mouse input.
- `bootstrap/` (in git soon): Enviroment for running PICO-8, including scripts, proot, and a minimal rootfs.
- `shim/`: Library LD_PRELOAD'ed into PICO-8 to handle streaming i/o and making sure SDL acts exactly as needed.

## Building
### Godot Frontend
1. Download [Godot](https://godotengine.org) version ≥4.4.1.
2. Put `package.dat` from Releases in the project ~~or build it from bootstrap/ (soon)~~; this is the bootstrap package and is pretty essential
3. In Godot, **Project > Install Android Build Template**
4. then just do the normal **Project > Export**

## 📱 Compatibility

The current version of the APK has the following requirements:

- **Operating System:** Android 9.0 (Pie) or higher (API level 28+)
- **Architecture:** 64-bit (arm64-v8a)
- **Note:** 32-bit devices (armeabi-v7a) and versions older than Android 9 are not supported.

## Support me ( this fork )
If you like this project and would like to support me for more improvementsyou cab buy me a coffee with ko-fi: https://ko-fi.com/macs34661
