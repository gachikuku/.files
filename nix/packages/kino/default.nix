{ lib, buildGoModule, fetchFromGitHub, makeWrapper, mpv }:

buildGoModule rec {
  pname = "kino";
  version = "0-unstable-2026-10-18";

  src = fetchFromGitHub {
    owner = "mmcdole";
    repo = "kino";
    rev = "ca313f5898c20a8c052ec6cbdc390adef59d35bb";
    hash = "sha256-sVfEqICSo0ZYH0kUnRNQJRUStlfyk4E0JFgchSwm7YM=";
  };

  vendorHash = "sha256-XNuGyFn1NEfffKA19NhMeXWRpSnoWp17NTlL2m1xqW0=";
  patches = [ ./jellyfin-mpv-progress.patch ];
  subPackages = [ "cmd/kino" ];
  ldflags = [ "-s" "-w" "-X main.Version=${version}" ];
  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram "$out/bin/kino" --prefix PATH : ${lib.makeBinPath [ mpv ]}
  '';

  meta = {
    description = "Terminal client for browsing Plex and Jellyfin and playing media in mpv";
    homepage = "https://github.com/mmcdole/kino";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "kino";
  };
}
