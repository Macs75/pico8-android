{
  description = "pico8-android development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              android-tools # adb, fastboot
              scrcpy        # screen mirroring
              jdk17         # for Godot Android export
            ];

            shellHook = ''
              echo ""
              echo "=== pico8-android dev shell ==="
              echo ""
              echo "  ADB commands:"
              echo "    adb devices                  — list connected devices"
              echo "    adb logcat -b crash          — view crash logs"
              echo "    adb logcat *:E               — errors only"
              echo "    adb logcat | grep -i pico    — filter pico8 logs"
              echo "    adb logcat --pid=\$(adb shell pidof io.wip.pico8)"
              echo "                                 — app-specific logs"
              echo ""
              echo "  Useful:"
              echo "    scrcpy                       — mirror device screen"
              echo "    adb install app.apk          — install APK"
              echo "    adb shell                    — device shell"
              echo ""
            '';
          };
        }
      );
    };
}
