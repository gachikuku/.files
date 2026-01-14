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
				system.primaryUser = "gachikuku";

				nixpkgs.config = {
					allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
						"discord"
						"ngrok"
					];
				};

				fonts = {
					packages = with pkgs; [
						go-font
						dina-font
						monaspace
					];
				};

				# allow oksh as a login shell
				environment.shells = [
					"/run/current-system/sw/bin/oksh"
				];

				environment.systemPackages = with pkgs; [
					amfora
					mtr
					tree-sitter
					radamsa
					watch
					mpv
					yt-dlp
					qemu
					aerc
					cargo
					cmake
					entr
					cmus
					colima
					uv
					coreutils
					discord
					docker
					dive
					fabric-ai
					fd
					ffmpeg
					socat
					ffuf
					feroxbuster
					fzf
					gnupg
					hashid
					go_1_24
					gopass
					gopass-jsonapi
					hashcat
					hexedit
					html-tidy
					htmlq
					httpx
					icdiff
					github-cli
					qrencode
					jq
					jsluice
					libxo
					lima
					llvm
					lynx
					mblaze
					mkalias
					mupdf
					naabu
					neovim
					ngrok
					nmap
					nuclei
					openvpn
					plan9port
					ripgrep
					rustc
					sacc
					senpai
					sfeed
					sqlmap
					stow
					oksh
					subfinder
					syncthing
					tmux
					tree
					vim
					wget
					exploitdb
					yazi
					nodejs_24
					aerospace
					w3m
					links2
				];

				homebrew = {
					enable = true;

					taps = [
						"chaychoong/tap"
					];

					casks = [
						"affinity-designer"
						"affinity-photo"
						"chromium"
						"ghostty"
						"hammerspoon"
						"wireshark"
						"trezor-suite"
					];

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
				};

				nix = {
					linux-builder.enable = true;
					settings.trusted-users = [ "@admin" ];
				};

				system.activationScripts.applications.text = let
					env = pkgs.buildEnv {
						name = "system-applications";
						paths = config.environment.systemPackages;
						pathsToLink = [ "/Applications" ];
					};
				in
					pkgs.lib.mkForce ''
					  echo "setting up /Applications..." >&2
					  rm -rf /Applications/Nix\ Apps
					  mkdir -p /Applications/Nix\ Apps
					  find ${env}/Applications -maxdepth 1 -type l -exec readlink '{}' + |
					  while read -r src; do
						app_name=$(basename "$src")
						${pkgs.mkalias}/bin/mkalias "$src" "/Applications/Nix Apps/$app_name"
					  done
					'';

				nix.settings.experimental-features = "nix-command flakes";

				system.configurationRevision = self.rev or self.dirtyRev or null;
				system.stateVersion = 5;
				nixpkgs.hostPlatform = "aarch64-darwin";
			};
		in
		{
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

			darwinPackages = self.darwinConfigurations."gachimacos".pkgs;
		};
}

