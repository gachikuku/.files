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

			sharedConfiguration = { ... }: {
				services.tailscale.enable = true;
				environment.variables.PI_OFFLINE = "1";
				time.timeZone = "Europe/Athens";
				system.configurationRevision = self.rev or self.dirtyRev or null;
				system.stateVersion = 5;
				nixpkgs.hostPlatform = "aarch64-darwin";
			};

			workstationConfiguration = { pkgs, config, lib, ... }: {
				system.primaryUser = username;

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

				nixpkgs.overlays = [
					(final: prev: {
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

						#steghide
						aerc
						aerospace
						amfora #gemini browser
						ares-cli
						binwalk
						browsh
						cacert
						cargo
						claude-code
						cmake
						cmus
						codex
						colima
						coreutils
						discord
						dive
						docker
						entr
						exiftool
						fd
						feroxbuster
						ffmpeg
						ffuf # remember uff and ffufai!
						frida-tools
						fzf
						gcc-arm-embedded
						gh
						gnupg
						gnuplot
						go
						gopass
						gopass-jsonapi
						hashcat
						hashid
						hexedit
						html-tidy
						htmlq
						httpx
						husky
						icdiff
						ideviceinstaller
						jq
						jsluice
						ledger
						libimobiledevice
						libretls
						libusbmuxd
						libxo
						lima
						links2
						llvm
						lynx
						mblaze
						mitmproxy
						mkalias
						mksh
						mpv
						mtr
						mupdf
						naabu
						neovim
						ngrok
						nmap
						nodejs_24
						nuclei
						oksh
						opencode
						openvpn
						pi-coding-agent
						pinentry_mac
						plan9port  # Plan 9 page(1) image viewer and user-space tools
						python312Packages.pycryptodome
						qemu
						radamsa
						radare2
						ripgrep
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
						terminal-notifier  # clickable agent-notify desktop pings
						tmux
						tor 
						torsocks
						tree
						tree-sitter
						trezorctl
						trezord
						usbfluxd
						uv
						vim
						w3m
						watch
						wget
						witnessme
						xdg-utils
						yazi
						yt-dlp
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
				programs.zsh = {
					enableCompletion = true;
					enableBashCompletion = false;
					enableGlobalCompInit = false;
					promptInit = "";
				};

			};
		in
			{
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
