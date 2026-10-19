{ lib, buildGoModule, fetchFromGitHub, makeWrapper, bash, fzf }:

buildGoModule {
  pname = "ccsession";
  version = "1.5.0";

  src = fetchFromGitHub {
    owner = "sorafujitani";
    repo = "ccsession";
    rev = "d0f7c1702e29e86db75c47ce49ebee529e4586ab";
    hash = "sha256-2xDhdqInl9+BGIYf+txH+BHfl+wEEkDg+1RQKglkFf8=";
  };

  # Search full IDs and labels, with an optional literal query. Use Codex's
  # read-only indexes for titles and previews instead of scanning huge logs.
  patches = [ ./search-and-index.patch ];
  vendorHash = "sha256-87X5go1iG4gqUTHXbZoxWuAhk+jWv6OBIQVb5UfFfzs=";
  subPackages = [ "cmd/ccsession" ];
  ldflags = [ "-s" "-w" "-X main.version=1.5.0" "-X main.commit=d0f7c17+local" ];

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ bash fzf ];
  checkPhase = ''
    runHook preCheck
    # Upstream's Claude directory-decoding fixture needs a temp root without
    # hyphens; the Nix build directory contains them.
    TMPDIR=/tmp go test ./...
    runHook postCheck
  '';
  postInstall = ''
    wrapProgram "$out/bin/ccsession" \
      --prefix PATH : ${lib.makeBinPath [ bash fzf ]} \
      --set-default CCSESSION_SOURCE codex \
      --set-default CCSESSION_PREVIEW_MESSAGES 40
    ln -s ccsession "$out/bin/cs"
  '';

  meta = {
    description = "Agent session picker with ID/label search and conversation previews";
    homepage = "https://github.com/sorafujitani/ccsession";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "cs";
  };
}
