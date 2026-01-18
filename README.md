# PICO-8 for Android

This application is a specialized frontend for the Android platform that allows you to run and play with the original PICO-8 (specifically the Raspberry Pi build) on your Android device.

**Note:** This application is a wrapper/launcher; it does **not** contain PICO-8 itself. You must provide your own legally purchased copy of the PICO-8 Raspberry Pi executable at the start of the application.

## ⚠️ Important Technical Details

### Android Version Target & Warning
To enable the execution of the external PICO-8 executable provided by the user, this application targets an older Android SDK version.
*   **Why?** Newer Android versions restrict the execution of binaries downloaded or copied to the device storage for security reasons. Targeting an older SDK bypasses this restriction.
*   **Result:** You may see a system warning stating that this app was built for an older version of Android. This is expected and necessary for the app to function.

### Storage Permissions
The application requires permission to access the device's storage (specifically the media/documents folder).
*   **Usage:** This is needed to copy the default PICO-8 configuration files into `/Documents/pico8/data`.
*   You will be asked to grant this permission upon first launch.

### 📱 Compatibility
The current version of the APK has the following requirements:
*   **Operating System:** Android 9.0 (Pie) or higher (API level 28+)
*   **Architecture:** 64-bit (arm64-v8a)
*   **Note:** 32-bit devices (armeabi-v7a) and versions older than Android 9 are not supported.


### User Data & Cartridges
The `/Documents/pico8/data` folder is automatically populated during the first execution of PICO-8, exactly mirroring the behavior of a standard PC installation.
*   **Cross-Platform Compatibility:** Because the structure is identical, if you have an existing PICO-8 installation on another platform, you can copy your `carts`, favorites, and save data directly into this folder.
*   **Migration:** simply copy your files into the corresponding subfolders in `/Documents/pico8/data` to carry over your progress and library to Android.
*   **Synchronization:** You can use external tools like **Syncthing** to keep this folder in sync with your other devices (PC, raspberry pi, etc.). Please refer to the specific documentation of your chosen tool for setup details.


## 🌟 Key Features (Fork)
This fork introduces several enhancements to improve the experience on Android devices:

*   **Landscape Mode:** Optimized UI and display for landscape orientation.
*   **Controller Support:** Full support for external game controllers.
*   **Android Handheld Support:** Tested and verified on devices like the **RG Cube**.
*   **Virtual Keyboard:** Access the Android keyboard at any time by sliding up from the bottom of the screen.
*   **Options Menu:** Access the side menu for settings and options by sliding from the left side of the screen.
*   **Frontend support:** Now you can use ES-DE to launch Pico-8 games with this application as alternative emulator. ( see release notes of v.0.0.7 waiting for integrated support from ES-DE team )
*   **Direct card launch:** You can now launch cards directly from any file manager. Moreover,   if you activate deep links, you can also launch cards directly from the https://www.lexaloffle.com/ website. Alternatively available on browser that support it is available "Send Link " and "Send Image" options to launch the card in this app.


## 📂 Project Structure
- `frontend/`: Godot app part; sets up environment and handles video output and keyboard/mouse input.
- `bootstrap/` (in git soon): Enviroment for running PICO-8, including scripts, proot, and a minimal rootfs.
- `shim/`: Library LD_PRELOAD'ed into PICO-8 to handle streaming i/o and making sure SDL acts exactly as needed.

## 🛠️ Building
### Godot Frontend
1. Download [Godot](https://godotengine.org) version ≥4.4.1.
2. Put `package.dat` from Releases in the project ~~or build it from bootstrap/ (soon)~~; this is the bootstrap package and is pretty essential
3. In Godot, **Project > Install Android Build Template**
4. then just do the normal **Project > Export**



## 🙏 Acknowledgments
First and foremost, a massive thank you to **[Zep (Joseph White)](https://www.lexaloffle.com/)**, the author of the fantastic **PICO-8** fantasy console.

A huge thank you to **[UnmatchedBracket](https://github.com/UnmatchedBracket)**, the original creator of this Android wrapper. He did all the heavy lifting of building the bridge between native PICO-8 and Android; without his incredible effort, this project would not be possible.

Also, a big thanks to **[kishan-dhankecha](https://github.com/kishan-dhankecha)** for his contributions and modifications to the original frontend which this fork builds upon.


## ☕ Support Me
If you enjoy this project and would like to support its ongoing development and future improvements, please consider buying me a coffee! Your support is greatly appreciated.

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/macs34661)
