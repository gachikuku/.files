{
	description = "nix-darwin";

	inputs = {
		nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
		nix-darwin.url = "github:LnL7/nix-darwin";
		nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
		nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
		fast-resume.url = "github:angristan/fast-resume";
		fast-resume.inputs.nixpkgs.follows = "nixpkgs";
	};

	outputs = inputs@{ self, nix-darwin, nixpkgs, nix-homebrew, ... }: let
		username = "gachikuku";

		# Run ./update-codex --switch to pin GitHub's Latest release and rebuild.
		# Keep immutable release URLs and checksums so rebuilds stay reproducible.
		codexRelease = {
			version = "0.162.1";
			hash = "sha256-iON8zd9aD06p3BvhPGaiqU+cLRoE86zpBT1xs5OeiF0=";
		};

		sharedConfiguration = { ... }: {
			services.tailscale.enable = true;
			environment.variables.PI_OFFLINE = "1";
			environment.etc."codex/requirements.toml".text = ''
          # Keep Codex in full-access mode even when selecting a Daybreak model.
          # Cyber models otherwise switch the active thread to Auto-review.
          allowed_approval_policies = [ "never" ]
          default_permissions = ":danger-full-access"

          [allowed_permission_profiles]
          ":danger-full-access" = true
        '';
			time.timeZone = "Europe/Athens";
			system.configurationRevision = self.rev or self.dirtyRev or null;
			system.stateVersion = 5;
			nixpkgs.hostPlatform = "aarch64-darwin";
		};

		workstationConfiguration = { pkgs, config, lib, ... }: {
			system.primaryUser = username;
			environment.variables.PKG_CONFIG_PATH =
				lib.makeSearchPath "lib/pkgconfig" [
					pkgs.radare2
					pkgs.libzip
					pkgs.zlib
					pkgs.lz4
					pkgs.xxhash
				];

			# List packages installed in system profile. To search by name, run:
			# $ nix-env -qaP | grep wget

			nixpkgs.config = {
				# Allow specific unfree packages
				allowUnfreePredicate =
					pkg:
					builtins.elem (lib.getName pkg) [
						"discord"
						"ngrok"
						"claude-code"
					];

			};

			nixpkgs.overlays = [
				(final: prev: {
					ccsession = final.callPackage ./packages/ccsession { };
					crunchyroll-tui = final.callPackage ./packages/crunchyroll-tui { };
					fast-resume = inputs.fast-resume.packages.${final.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
						# ID/regex search, chat previews, and main-session Codex resumes.
						src = inputs.fast-resume.outPath;
						patches = (old.patches or [ ]) ++ [ ./packages/fast-resume/fuzzy-session-ids.patch ];
						nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.makeBinaryWrapper ];
						postFixup = (old.postFixup or "") + ''
							# Use light colors without terminal capability probes on startup.
							wrapProgram "$out/bin/fr" --set-default FAST_RESUME_NO_IMAGES true \
								--set-default FAST_RESUME_THEME light \
								--set-default FAST_RESUME_COMPACT true
						'';
					});
					kino = final.callPackage ./packages/kino { };

					codex = final.stdenvNoCC.mkDerivation {
						pname = "codex";
						inherit (codexRelease) version;
						src = final.fetchurl {
							url = "https://github.com/openai/codex/releases/download/rust-v${codexRelease.version}/codex-package-aarch64-apple-darwin.tar.gz";
							inherit (codexRelease) hash;
						};
						sourceRoot = ".";
						dontBuild = true;
						# Preserve upstream signatures and the bundled runtime layout.
						dontFixup = true;
						nativeBuildInputs = [ final.installShellFiles ];
						installPhase = ''
                  runHook preInstall
                  export CODEX_HOME="$TMPDIR/codex-home"
                  mkdir -p "$CODEX_HOME"
                  mkdir -p "$out"
                  cp -R bin codex-package.json codex-path codex-resources "$out/"
                  installShellCompletion --cmd codex \
                    --bash <("$out/bin/codex" completion bash) \
                    --fish <("$out/bin/codex" completion fish) \
                    --zsh <("$out/bin/codex" completion zsh)
                  runHook postInstall
                '';
						doInstallCheck = true;
						nativeInstallCheckInputs = [ final.versionCheckHook ];
						meta = {
							description = "Codex CLI from the official GitHub release";
							homepage = "https://github.com/openai/codex";
							license = lib.licenses.asl20;
							mainProgram = "codex";
							platforms = [ "aarch64-darwin" ];
						};
					};

					frida-tools = prev.frida-tools.overridePythonAttrs (_: rec {
						version = "14.11.0";
						src = final.fetchPypi {
							pname = "frida_tools";
							inherit version;
							hash = "sha256-uMdy5ZUCvkO3bfn+zK3V00K1yjJQZt0MI4TmP6iNqSE=";
						};
					});

					# waymore 8.9 caches Common Crawl's index beside its Python module.
					# Nix store paths are immutable, so move that cache to XDG_CACHE_HOME.
					waymore = prev.waymore.overrideAttrs (old: {
						postPatch = (old.postPatch or "") + ''
                  substituteInPlace waymore/waymore.py \
                    --replace-fail \
                    '        collinfoPath = str(Path(__file__).parent.resolve()) + "/collinfo.json"' \
                    '        cache_root = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "waymore"; cache_root.mkdir(parents=True, exist_ok=True); collinfoPath = str(cache_root / "collinfo.json")'
                '';
					});

					# One-line scrolling, shortcut actions, and a block cursor in senpai.
					senpai = prev.senpai.overrideAttrs (old: {
						postPatch = (old.postPatch or "") + ''
                  substituteInPlace app.go \
                    --replace-fail 'ScrollUpBy(4)' 'ScrollUpBy(1)' \
                    --replace-fail 'ScrollDownBy(4)' 'ScrollDownBy(1)' \
                    --replace-fail 'ScrollChannelUpBy(4)' 'ScrollChannelUpBy(1)' \
                    --replace-fail 'ScrollChannelDownBy(4)' 'ScrollChannelDownBy(1)' \
                    --replace-fail 'ScrollMemberUpBy(4)' 'ScrollMemberUpBy(1)' \
                    --replace-fail 'ScrollMemberDownBy(4)' 'ScrollMemberDownBy(1)'
                  substituteInPlace app.go --replace-fail 'case "scroll-up":' 'case "scroll-up-line":
                    app.win.ScrollUpBy(1)
                  case "scroll-down-line":
                    app.win.ScrollDownBy(1)
                  case "scroll-up":'
                  substituteInPlace ui/editor.go ui/ui.go \
                    --replace-fail 'vaxis.CursorBeam' 'vaxis.CursorBlock'
                  gofmt -w app.go
                '';
					});

					pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
						(
							pythonFinal: pythonPrev:
							let
								# Share the Frida version between CLI tools and Python controllers.
								fridaPython = pythonPrev.frida-python.overridePythonAttrs (_: rec {
									version = "17.23.3";
									src = final.fetchPypi {
										pname = "frida";
										inherit version;
										format = "wheel";
										platform = "macosx_11_0_arm64";
										abi = "abi3";
										python = "cp37";
										dist = "cp37";
										hash = "sha256-UaY7owWhEuzuHSGkaphwAfr7vM/M91qBZy3nBpu+iRc=";
									};
								});

								qh3_1 = pythonPrev.qh3.overridePythonAttrs (_: rec {
									version = "1.9.4";
									src = final.fetchFromGitHub {
										owner = "jawah";
										repo = "qh3";
										tag = "v${version}";
										hash = "sha256-Mu9wvwHHn5wZfE+TdMu/nr2B7+WbFhFHDoItDs6rRPM=";
									};
									cargoDeps = final.rustPlatform.fetchCargoVendor {
										pname = "qh3";
										inherit version src;
										hash = "sha256-bwdaM+DdXm5YpzVlyYdDqnR+QQ0dY199DYN2g33RvCs=";
									};
								});
							in {
								frida-python = fridaPython;

								asn1_2 = pythonPrev.asn1.overridePythonAttrs (_: rec {
									version = "2.8.0";
									src = final.fetchPypi {
										pname = "asn1";
										inherit version;
										hash = "sha256-rfd93CcHz0IMDq47me4w6ROvzwk2Rn1CZpggzmt9FQo=";
									};
								});

								# PyIMG4 has not yet been ported to asn1 3.x.
								pyimg4 = pythonPrev.pyimg4.overridePythonAttrs (old: {
									dependencies =
										builtins.filter
											(dependency: lib.getName dependency != "asn1")
											old.dependencies
										++ [
											pythonFinal.asn1_2
										];
									meta = old.meta // {
										broken = false;
									};
								});

								pymobiledevice3 = pythonPrev.pymobiledevice3.overridePythonAttrs (old: {
									dependencies = map (
										dependency:
											if lib.getName dependency == "qh3"
											then qh3_1
											else dependency
									) old.dependencies;
								});
							}
						)
					];

					witnessme =
						(prev.witnessme.override { python3 = final.python313; }).overrideAttrs
							(old: {
								postPatch = (old.postPatch or "") + ''
                      substituteInPlace witnessme/signatures.py \
                        --replace-fail "import pkg_resources" "" \
                        --replace-fail 'pkg_resources.resource_filename(__name__, "signatures")' 'pathlib.Path(__file__).parent / "signatures"'
                    '';
							});
				})
			];

			fonts = {
				packages = with pkgs; [
					go-font
					dina-font
					monaspace
				];
			};

			#nixpkgs.config.permittedInsecurePackages = [
			#  "python3.13-ecdsa-0.19.1"
			#];

			environment.systemPackages = with pkgs; [
				#steghide
				aerc
				aerospace
				android-tools
				ares-cli
				awscli2
				binwalk
				pandoc
				vncdotool
				python313Packages.pymobiledevice3
				python313Packages.vncdotool
				browsh
				cacert
				cargo
				ccsession
				claude-code
				cmake
				cmus
				codex
				colima
				coreutils
				crunchyroll-tui
				kino
				discord
				dive
				docker
				dpkg
				entr
				exiftool
				omp
				fast-resume
				fd
				feroxbuster
				ffmpeg
				ffuf # remember uff and ffufai!
				frida-tools
				fzf
				gcc-arm-embedded
				gh
				ghidra
				(runCommand "ghidra-cli" { } ''
              mkdir -p $out/bin
              ln -s ${ghidra}/lib/ghidra/ghidraRun $out/bin/ghidraRun
              ln -s ${ghidra}/lib/ghidra/support/analyzeHeadless $out/bin/analyzeHeadless
            '')
				(writeShellScriptBin "swift-demangle" ''
              exec /usr/bin/xcrun swift-demangle "$@"
            '')
				gnupg
				gnumake
				gnuplot
				go
				gopass
				gopass-jsonapi
				gungnir
				hashcat
				hashid
				hexedit
				html-tidy
				htmlq
				httpx
				husky
				icdiff
				ideviceinstaller
				ipsw
				(
					let
						jtool2Archive = fetchurl {
							url = "https://www.newosxbook.com/tools/jtool2.tgz";
							hash = "sha256-mZRd60UlimGZh3tXPHhVm4uOdMzEBwpBr7ZdVMvKHKk=";
						};
					in
					runCommand "jtool2-2026-02-14"
						{
							nativeBuildInputs = [
								gnutar
								gzip
								ldid
								makeWrapper
							];
						}
						''
                  mkdir -p $out/bin $out/libexec $out/share/jtool2
                  tar -xzf ${jtool2Archive}
                  install -m755 jtool2 disarm $out/libexec/
                  ldid -S $out/libexec/jtool2
                  ldid -S $out/libexec/disarm
                  makeWrapper /usr/bin/arch $out/bin/jtool2 \
                    --add-flags -x86_64 --add-flags $out/libexec/jtool2
                  makeWrapper /usr/bin/arch $out/bin/disarm \
                    --add-flags -x86_64 --add-flags $out/libexec/disarm
                  install -m644 matchers.txt WhatsNew.txt $out/share/jtool2/
                ''
				)
				(
					let
						version = "2.0.8";
						coreArchive = fetchurl {
							url = "https://github.com/Lakr233/vphone-cli/releases/download/${version}/VPhone-${version}.zip";
							hash = "sha256-Xtwta2jczQXV7nZSVWySueUSVV9/TYmuRh08MQb7hKk=";
						};
						launchpadArchive = fetchurl {
							url = "https://github.com/Lakr233/vphone-cli/releases/download/${version}/vphone-launchpad-${version}-notarized.zip";
							hash = "sha256-fTJmr+GIMrV2mvpnHzaSMgvADbhUeYZm8FZJ5KOjomM=";
						};
					in
					runCommand "vphone-${version}" { nativeBuildInputs = [ unzip ]; } ''
                mkdir -p $out/bin $out/libexec $out/Applications
                unzip -q ${coreArchive} -d $out/libexec
                unzip -q ${launchpadArchive} -d $out/Applications
                mv "$out/Applications/vphone-launchpad-${version}.app" \
                  "$out/Applications/VPhone Launchpad.app"
                ln -s $out/libexec/VPhone.bundle/Contents/MacOS/vphone-cli $out/bin/vphone-cli
                ln -s $out/libexec/VPhone.bundle/Contents/MacOS/vphone-vm $out/bin/vphone-vm
              ''
				)
				jq
				jsluice
				ledger
				ldid
				libfido2 # fido2-token and lower-level FIDO2 utilities
				libimobiledevice
				libretls
				libusbmuxd
				libxo
				lima
				llvm
				lynx
				mblaze
				mitmproxy
				mkalias
				mksh
				mpv
				mtr
				mupdf
				mullvad
				naabu
				neovim
				ngrok
				nmap
				nodejs_24
				nuclei
				oksh
				opencode
				opensc # opensc-tool, pkcs11-tool, and smart-card inspection
				openssh # FIDO2-capable ssh/ssh-keygen (unlike Apple's build)
				openvpn
				pi-coding-agent
				pinentry_mac
				pkg-config
				p7zip
				plan9port # Plan 9 page(1) image viewer and user-space tools
				python312Packages.pycryptodome
				# Python environment for custom Frida controllers. frida-tools ships
				# its own wrapped interpreter, which is not importable by /usr/bin/python3.
				(python313.withPackages (ps: [
					ps.beautifulsoup4
					ps.capstone
					ps.cryptography
					ps.dkimpy
					ps.faker
					ps.frida-python
					ps.lief
					ps.macholib
					ps.mitmproxy
					ps.playwright
					ps.pytest
					ps.r2pipe
					ps.requests
				]))
				# nixpkgs' current angr cohort is version-skewed. Keep it isolated
				# from the shared Python environment and bootstrap one pinned venv.
				(writeShellScriptBin "angr-python" ''
              set -eu
              angr_env="''${XDG_CACHE_HOME:-/Users/gachikuku/.cache}/codex-angr-9.2.154"
              if ! "$angr_env/bin/python" -c 'import angr; assert angr.__version__ == "9.2.154"' >/dev/null 2>&1; then
                ${uv}/bin/uv venv --clear --python ${python313}/bin/python3 "$angr_env"
                ${uv}/bin/uv pip install --python "$angr_env/bin/python" \
                  'angr==9.2.154' 'pycparser==2.22'
              fi
              exec "$angr_env/bin/python" "$@"
            '')
				qemu
				radamsa
				radare2
				ripgrep
				ruff
				rustc
				rustup
				sc-im
				senpai
				sfeed
				socat
				speedtest-cli
				sqlmap
				stow
				subfinder
				syncthing
				tailscale
				tealdeer
				terminal-notifier # clickable agent-notify desktop pings
				tmux
				tor
				torsocks
				tree
				tree-sitter
				trezord
				usbfluxd
				uv
				vim
				w3m
				watch
				waymore
				webdump
				wget
				witnessme
				xdg-utils
				yazi
				yt-dlp
				yubico-piv-tool
				yubikey-manager # ykman
				zbar
				zsteg
			];

			homebrew = {
				enable = true;

				# monero (monerod + GUI) is managed by ~/.local/bin/monero-update,
				# which installs the OFFICIAL binaries and verifies them against
				# binaryFate's PGP-signed hashes.txt. nixpkgs monero-cli is linux-only,
				# and brew ships its own bottle (can't match the official binary hash).
				brews = [
					"duti" # Register the Gopher URL handler with macOS.
				];

				taps = [
					"chaychoong/tap"
				];

				casks = [
					"affinity-designer"
					"trezor-suite"
					"affinity-photo"
					"chromium"
					"google-chrome"
					"ghostty"
					"hammerspoon"
					"wireshark-app"
				];
				#onActivation.cleanup = "zap";
				onActivation.autoUpdate = true;
				onActivation.upgrade = true;
			};

			system.defaults = {
				NSGlobalDomain."com.apple.sound.beep.feedback" = 0;
				NSGlobalDomain.AppleICUForce24HourTime = true;
				NSGlobalDomain.AppleShowAllExtensions = true;
				NSGlobalDomain.AppleShowAllFiles = true;
				NSGlobalDomain.InitialKeyRepeat = 10;
				NSGlobalDomain.KeyRepeat = 2;
				NSGlobalDomain.NSAutomaticCapitalizationEnabled = false;
				NSGlobalDomain.NSAutomaticDashSubstitutionEnabled = false;
				NSGlobalDomain.NSAutomaticInlinePredictionEnabled = false;
				NSGlobalDomain.NSAutomaticPeriodSubstitutionEnabled = false;
				NSGlobalDomain.NSAutomaticQuoteSubstitutionEnabled = false;
				NSGlobalDomain.NSAutomaticSpellingCorrectionEnabled = false;
				NSGlobalDomain._HIHideMenuBar = false;
				controlcenter.Sound = false;
				dock.autohide = true;
				dock.orientation = "left";
				dock.persistent-apps = [
					"/System/Applications/Calendar.app"
				];
				dock.autohide-delay = 0.24;
				dock.show-recents = false;
				dock.showhidden = true;
				dock.static-only = true;
				dock.tilesize = 48;
				dock.wvous-br-corner = 1;
				#finder.AppleShowAllFiles = true;
				finder.FXPreferredViewStyle = "clmv";
				finder.ShowExternalHardDrivesOnDesktop = false;
				finder.ShowPathbar = true;
				finder.ShowStatusBar = true;
				finder._FXShowPosixPathInTitle = true;
				loginwindow.GuestEnabled = false;
				loginwindow.SHOWFULLNAME = true;
				loginwindow.autoLoginUser = username;
				menuExtraClock.ShowAMPM = false;
				menuExtraClock.ShowDayOfWeek = false;
				screencapture.location = "~/Pictures/Screenshots";
				screensaver.askForPassword = false;
				screensaver.askForPasswordDelay = 0;
			};

			security.sudo.extraConfig = ''
            ${username} ALL=(ALL) NOPASSWD: ALL
          '';

			# Keep the login keychain unlocked for the entire user session.
			launchd.user.agents."keychain-no-timeout".serviceConfig = {
				ProgramArguments = [
					"/usr/bin/security"
					"set-keychain-settings"
					"/Users/${username}/Library/Keychains/login.keychain-db"
				];
				RunAtLoad = true;
			};

			# Remove authentication sheets from the System Settings rights used on this
			# Mac.
			system.activationScripts.postActivation.text = lib.mkAfter ''
            for authorizationRight in \
              system.preferences \
              system.preferences.accessibility \
              system.preferences.accounts \
              system.preferences.continuity \
              system.preferences.datetime \
              system.preferences.energysaver \
              system.preferences.location \
              system.preferences.network \
              system.preferences.nvram \
              system.preferences.parental-controls \
              system.preferences.printing \
              system.preferences.security \
              system.preferences.security.remotepair \
              system.preferences.sharing \
              system.preferences.softwareupdate \
              system.preferences.startupdisk \
              system.preferences.timemachine \
              system.preferences.version-cue \
              com.apple.DiskManagement.reserveKEK \
              system.services.directory.configure
            do
              if ! /usr/bin/security authorizationdb read "$authorizationRight" 2>/dev/null \
                | /usr/bin/grep -q '<string>allow</string>'; then
                /usr/bin/security authorizationdb write "$authorizationRight" allow \
                  >/dev/null 2>&1
              fi
            done
          '';

			networking = {
				localHostName = "gachimacos";
				computerName = "gachimacos";
				hostName = "gachimacos";
			};

			system.keyboard = {
				enableKeyMapping = true;
				remapCapsLockToControl = true;
				#swapLeftCommandAndLeftAlt = true;
			};

			#launchd.user.agents.sfeed_update = {
			#  serviceConfig = {
			#    ProgramArguments = [ "${pkgs.sfeed}/bin/sfeed_update" "~/.sfeed/sfeedrc" ];
			#    #StartCalendarInterval = { Minute = 0; };
			#    StartInterval = 60; # Run every 60 seconds (1 minute)
			#  };
			#};

			# OFFICIAL monero (monerod + GUI), verified against binaryFate's
			# PGP-signed hashes.txt. Updated MANUALLY: run `monero-update`
			# (or `monero-update -c` to just check). See ~/.files/bin/bin/monero-update.

			nix = {
				gc = {
					automatic = true;
					interval = [{ Hour = 3; Minute = 15; }];
					options = "--delete-older-than 30d";
				};

				linux-builder = {
					enable = true;
					package = pkgs.darwin.linux-builder-vz;
				};

				# This line is a prerequisite
				settings.trusted-users = [ "@admin" ];
			};

			# mkalias acitvation script so spotlight can spot it
			system.activationScripts.applications.text =
				let
					env = pkgs.buildEnv {
						name = "system-applications";
						paths = config.environment.systemPackages;
						pathsToLink = [ "/Applications" ];
					};
				in
				pkgs.lib.mkForce ''
              # Set up applications.
              echo "setting up /Applications..." >&2
              rm -rf /Applications/Nix\ Apps
              mkdir -p /Applications/Nix\ Apps
              find ${env}/Applications -maxdepth 1 -type l -exec readlink '{}' + |
              while read -r src; do
                app_name=$(basename "$src")
                echo "copying $src" >&2
                ${pkgs.mkalias}/bin/mkalias "$src" "/Applications/Nix Apps/$app_name"
              done

            '';

			# Necessary for using flakes on this system.
			nix.settings.experimental-features = "nix-command flakes";

			# Enable alternative shell support in nix-darwin.
			# programs.fish.enable = true;
			programs.zsh = {
				enableCompletion = true;
				enableBashCompletion = false;
				enableGlobalCompInit = false;
				promptInit = "";
			};
		};
	in {
		darwinConfigurations."gachimacos" = nix-darwin.lib.darwinSystem {
			specialArgs = { inherit username; };
			modules = [
				sharedConfiguration
				workstationConfiguration
				nix-homebrew.darwinModules.nix-homebrew
				{
					nix-homebrew = {
						enable = true;
						enableRosetta = true;
						enableZshIntegration = false;
						user = username;
					};
				}
			];
		};

		# Expose the workstation package set for convenience and compatibility.
		darwinPackages = self.darwinConfigurations."gachimacos".pkgs;
	};
}
