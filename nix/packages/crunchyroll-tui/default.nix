{ lib, rustPlatform, fetchFromGitHub, makeWrapper, runtimeShell, ffmpeg, mpv }:

rustPlatform.buildRustPackage {
  pname = "crunchyroll-tui";
  version = "0.1.0-unstable-2026-09-24";

  src = fetchFromGitHub {
    owner = "xhaiwa";
    repo = "crunchyroll-tui";
    rev = "5981be273ae923bb6f54eb5b95b133f68f07617f";
    hash = "sha256-w0HH28MHgBJQdFsheQpGDk/9+bKfOSpGPyzEoYlfRkQ=";
  };

  cargoLock.lockFile = ./Cargo.lock;
  patches = [ ./macos-mpv-pipe.patch ];
  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram "$out/bin/crunchyroll-tui" \
      --prefix PATH : ${lib.makeBinPath [ ffmpeg mpv ]}

    # Device credentials are read at runtime, never included in the Nix store.
    cat > "$out/bin/crunchy" <<'SCRIPT'
    #!${runtimeShell}
    set -eu
    umask 077
    crunchy_data_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/crunchyroll-tui"
    mkdir -p "$crunchy_data_dir"
    cd "$crunchy_data_dir"
    SCRIPT
    echo 'exec '"$out"'/bin/crunchyroll-tui --tui "$@"' >> "$out/bin/crunchy"
    chmod +x "$out/bin/crunchy"
  '';

  meta = {
    description = "Browse Crunchyroll in the terminal and stream to mpv";
    homepage = "https://github.com/xhaiwa/crunchyroll-tui";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.unix;
    mainProgram = "crunchy";
  };
}
