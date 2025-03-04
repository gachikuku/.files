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
				# List packages installed in system profile. To search by name, run:
				# $ nix-env -qaP | grep wget

				nixpkgs.config = {
					# Allow specific unfree packages
					allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
						"discord"
						"ngrok"
						"raycast"
					];

				};

				fonts = {
					packages = with pkgs; 
						[
							go-font
						];
				};


				environment.systemPackages = with pkgs;
					[ 
						aerc
						cargo
						cmake
						cmus
						colima
						coreutils
						discord
						docker
						fabric-ai
						fd
						ffmpeg
						ffuf
						fzf
						gnupg
						go_1_24
						gopass
						gopass-jsonapi
						hashcat
						hexedit
						html-tidy
						icdiff
						jq
						libxo
						lima
						llvm
						mkalias
						mpv
						neovim
						ngrok
						nmap
						nodejs_22
						plan9port
						python312Full
						python312Packages.ipython
						raycast
						ripgrep
						rustc
						sacc
						senpai
						sqlmap
						stow
						tailscale
						tealdeer
						tmux
						tree
						vim
						wget
						wireguard-tools
						witnessme
						yazi
						zbar
					];


				homebrew = {
					enable = true;
					casks = [
						"affinity-designer"
						"affinity-photo"
						"chromium"
						"ghostty"
						"hammerspoon"
						"wireshark"
					];
					onActivation.cleanup = "zap";
					onActivation.autoUpdate = true;
					onActivation.upgrade = true;
				};

				system.defaults = {
					NSGlobalDomain."com.apple.sound.beep.feedback" = 0;
					NSGlobalDomain.AppleICUForce24HourTime = true;
					NSGlobalDomain.AppleInterfaceStyle = "Dark";
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
				};


				# mkalias acitvation script so spotlight can spot it
				system.activationScripts.applications.text = let
					env = pkgs.buildEnv {
						name = "system-applications";
						paths = config.environment.systemPackages;
						pathsToLink = "/Applications";
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
