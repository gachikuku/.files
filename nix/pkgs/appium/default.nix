{
  bash,
  buildNpmPackage,
  lib,
  nodejs_24,
}:
buildNpmPackage {
  pname = "h4c-appium";
  version = "3.6.0-xcuitest-12.5.0";
  src = ./.;

  npmDepsHash = "sha256-RZTw6tQcB2GHyElk1SQ8oXRJRiFKYjBSAQCBVUmbKcs=";
  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall

    appium_home="$out/lib/appium-home"
    mkdir -p "$appium_home" "$out/bin"
    cp package.json package-lock.json "$appium_home/"
    cp -R node_modules "$appium_home/"

    cat > "$out/bin/appium" <<'EOF'
    #!@bash@
    set -euo pipefail
    runtime_home="''${APPIUM_HOME:-''${XDG_DATA_HOME:-$HOME/.local/share}/h4c-appium}"
    mkdir -p "$runtime_home/node_modules"
    ln -sfn "@appium_home@/node_modules/appium-xcuitest-driver" \
      "$runtime_home/node_modules/appium-xcuitest-driver"
    cp -f "@appium_home@/package.json" "@appium_home@/package-lock.json" "$runtime_home/"
    export APPIUM_HOME="$runtime_home"
    export PATH="@node_path@:$PATH"
    exec "@appium_home@/node_modules/.bin/appium" "$@"
    EOF
    substituteInPlace "$out/bin/appium" \
      --replace-fail '@bash@' '${lib.getExe bash}' \
      --replace-fail '@appium_home@' "$appium_home" \
      --replace-fail '@node_path@' '${lib.makeBinPath [ nodejs_24 ]}'
    chmod +x "$out/bin/appium"

    runHook postInstall
  '';

  meta = {
    description = "Pinned Appium with the XCUITest driver for h4c-mini";
    homepage = "https://appium.io/";
    license = lib.licenses.asl20;
    mainProgram = "appium";
    platforms = lib.platforms.darwin;
  };
}
