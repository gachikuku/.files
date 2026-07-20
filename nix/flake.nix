{
	description = "nix-darwin";

	inputs = {
		nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
		nix-darwin.url = "github:LnL7/nix-darwin";
		nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
		nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
	};

	outputs = inputs@{ self, nix-darwin, nixpkgs, nix-homebrew }:
		let
			username = "gachikuku";
			configuration = { pkgs, config, lib, ... }: {
				system.primaryUser = "gachikuku";  # Replace with your actual username if different
				# List packages installed in system profile. To search by name, run:
				# $ nix-env -qaP | grep wget

				nixpkgs.config = {
					# Allow specific unfree packages
					allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
						"discord"
						"ngrok"
						"claude-code"
					];

				};

				# cmux: nixpkgs is stuck on 0.64.10, but the copy-mode cursor-nav fix
				# and the "vim keys swallowed under non-ASCII input sources" fix both
				# landed upstream in 0.64.13. Override the prebuilt DMG to 0.64.16 until
				# nixpkgs catches up (then this block can be removed).
				nixpkgs.overlays = [
					(final: prev: {
						cmux = prev.cmux.overrideAttrs (old: {
							version = "0.64.16";
							src = prev.fetchurl {
								url = "https://github.com/manaflow-ai/cmux/releases/download/v0.64.16/cmux-macos.dmg";
								hash = "sha256-QB/2emBrAzqkcKaLrVUZanK4qXHSma4CeJM2PwGhmXI=";
							};
						});
						trezorctl = let py = final.python313Packages; in
							py.toPythonApplication (py.trezor.overridePythonAttrs (old: {
								dependencies = old.dependencies ++ old.optional-dependencies.full;
							}));
						witnessme = (prev.witnessme.override { python3 = final.python313; }).overrideAttrs (old: {
							postPatch = (old.postPatch or "") + ''
								substituteInPlace witnessme/signatures.py \
									--replace-fail "import pkg_resources" "" \
									--replace-fail 'pkg_resources.resource_filename(__name__, "signatures")' 'pathlib.Path(__file__).parent / "signatures"'
							'';
						});
					})
				];

				services.tailscale.enable = true;

				fonts = {
					packages = with pkgs; 
						[
							go-font
							dina-font
							monaspace
						];
				};

				#nixpkgs.config.permittedInsecurePackages = [
				#	"python3.13-ecdsa-0.19.1"
				#];

				environment.systemPackages = with pkgs;
					[ 
						ares-cli
						amfora #gemini browser
						mtr
						libretls
						cacert
						husky
						radamsa
						mpv
						yt-dlp
						gcc-arm-embedded
						cmux
						rustup
						radare2
						qemu
						aerc
						pinentry_mac
						cargo
						go
						trezorctl
						trezord
						speedtest-cli
						codex
						cmake
						entr
						cmus
						gnuplot
						ledger
						colima
						gh
						uv
						coreutils
						discord
						docker
							dive
						fabric-ai
						fd
						ffmpeg
						socat
						ffuf # remember uff and ffufai!
						feroxbuster
						fzf
						gnupg
						hashid
						gopass
						gopass-jsonapi
						hashcat
						hexedit
						html-tidy
						htmlq
						browsh
						oksh
						httpx
						icdiff
						jq
						jsluice
						libxo
						lima
						llvm
						sc-im
						lynx
						mblaze
						python312Packages.pycryptodome
						mkalias
						mupdf
						naabu
						neovim
						tree-sitter
						ngrok
						texliveFull
						nmap
						nuclei
						openvpn
						opencode
						claude-code
						pi-coding-agent
						ripgrep
						rustc
						senpai
						sfeed
						binwalk
						exiftool
						#steghide
						zsteg
						sqlmap
						stow
						subfinder
						syncthing
						tailscale
						tealdeer
						terminal-notifier  # clickable agent-notify desktop pings
						tmux
						tree
						vim
						wget
						witnessme
						xdg-utils
						yazi
						nodejs_24
						zbar
						oksh
						mksh
						aerospace
						w3m
						links2
					];


				homebrew = {
					enable = true;

					# monero (monerod + GUI) is managed by ~/.local/bin/monero-update,
					# which installs the OFFICIAL binaries and verifies them against
					# binaryFate's PGP-signed hashes.txt. nixpkgs monero-cli is linux-only,
					# and brew ships its own bottle (can't match the official binary hash).
					brews = [
						"cliproxyapi"
					];

					taps = [
						"chaychoong/tap"
					];


					casks = [
						"affinity-designer"
						"trezor-suite"
						"affinity-photo"
						"chromium"
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
					menuExtraClock.ShowAMPM = false;
					menuExtraClock.ShowDayOfWeek = false;
					screencapture.location = "~/Pictures/Screenshots";
				};

				networking = {
					localHostName = "gachimacos";
					computerName = "gachimacos";
					hostName = "gachimacos";
				};

				time.timeZone = "Europe/Athens";

				system.keyboard = {
					enableKeyMapping = true;
					remapCapsLockToControl = true;
					#swapLeftCommandAndLeftAlt = true;
				};

				#launchd.user.agents.sfeed_update = {
				#	serviceConfig = {
				#		ProgramArguments = [ "${pkgs.sfeed}/bin/sfeed_update" "~/.sfeed/sfeedrc" ];
				#		#StartCalendarInterval = { Minute = 0; };
				#		StartInterval = 60; # Run every 60 seconds (1 minute)
				#	};
				#};

				# OFFICIAL monero (monerod + GUI), verified against binaryFate's
				# PGP-signed hashes.txt. Updated MANUALLY: run `monero-update`
				# (or `monero-update -c` to just check). See ~/.files/bin/bin/monero-update.

				nix = {
					linux-builder.enable = true;

					# This line is a prerequisite
					settings.trusted-users = [ "@admin" ];
				};


				# mkalias acitvation script so spotlight can spot it
				system.activationScripts.applications.text = let
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

				# Set Git commit hash for darwin-version.
				system.configurationRevision = self.rev or self.dirtyRev or null;

				# Used for backwards compatibility, please read the changelog before changing.
				# $ darwin-rebuild changelog
				system.stateVersion = 5;

				# The platform the configuration will be used on.
				nixpkgs.hostPlatform = "aarch64-darwin";
			};
		in
			{
			# Build darwin flake using:
			# $ darwin-rebuild build --flake .#gabbass-MacBook-Pro
			darwinConfigurations."gachimacos" = nix-darwin.lib.darwinSystem {
				modules = [ 
					configuration 
					nix-homebrew.darwinModules.nix-homebrew
					{
						nix-homebrew = {
							enable = true;
							enableRosetta = true;
							user = "gachikuku";
						};
					}
				];
			};

			# NOT DEFAULT: Expose the package set, including overlays, for convenience.
			darwinPackages = self.darwinConfigurations."gachimacos".pkgs;
		};

}
