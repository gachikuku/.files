{
	description = "nix-darwin";

	inputs = {
		nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
		nix-darwin.url = "github:LnL7/nix-darwin";
		nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
	};

	outputs = inputs@{ self, nix-darwin, nixpkgs }:
		let
			username = "gachikuku";
			configuration = { pkgs, config, ... }: {
				# List packages installed in system profile. To search by name, run:
				# $ nix-env -qaP | grep wget
				environment.systemPackages = with pkgs;
					[ 
						aerc
						mkalias
						coreutils-full
						gnupg
						gopass
						kitty
						neovim
						nodejs_23
						senpai
						stow
						tailscale
						tmux
						vim
						wget
					];

				system.keyboard = {
					enableKeyMapping = true;
					remapCapsLockToControl = true;
				};

				system.defaults = {
					NSGlobalDomain."com.apple.sound.beep.feedback" = 0;
					NSGlobalDomain.AppleICUForce24HourTime = true;
					NSGlobalDomain.AppleShowAllExtensions = true;
					NSGlobalDomain.InitialKeyRepeat = 0;
					NSGlobalDomain.KeyRepeat = 2;
					NSGlobalDomain.NSAutomaticCapitalizationEnabled = false;
					NSGlobalDomain.NSAutomaticDashSubstitutionEnabled = false;
					NSGlobalDomain.NSAutomaticInlinePredictionEnabled = false;
					NSGlobalDomain.NSAutomaticSpellingCorrectionEnabled = false;
					controlcenter.Sound = true;
					dock.autohide = true;
					dock.orientation = "left";
					menuExtraClock.ShowAMPM = false;
					menuExtraClock.ShowDayOfWeek = false;
					screencapture.location = "~/Screenshots";
					finder.FXPreferredViewStyle = "clmv";
				};

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

				services.nix-daemon.enable = true;

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
				modules = [ configuration ];
			};

			# NOT DEFAULT: Expose the package set, including overlays, for convenience.
			# darwinPackages = self.darwinConfigurations."gachimacos".pkgs;
		};
}
