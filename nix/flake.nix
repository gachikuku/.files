{
  description = "nix-darwin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs }:
  let
    configuration = { pkgs, ... }: {
      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      environment.systemPackages = with pkgs;
        [ 
	  vim
	  gnupg
	  coreutils-full
	  gopass
	  tailscale
	  aerc
	  senpai
	  stow
	  tmux
        ];

      system.defaults = {
        dock.autohide = true;
	NSGlobalDomain.AppleICUForce24HourTime = true;
      };

      system.keyboard = {
        enableKeyMapping = true;
        remapCapsLockToControl = true;
      };

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
    darwinPackages = self.darwinConfigurations."gachimacos".pkgs;
  };
}
