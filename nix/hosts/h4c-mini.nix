{ username, pkgs, ... }:
{
  system.primaryUser = username;

  networking = {
    localHostName = "h4c-mini";
    computerName = "h4c-mini";
    hostName = "h4c-mini";

    applicationFirewall = {
      enable = true;
      blockAllIncoming = false;
      allowSigned = true;
      allowSignedApp = false;
      enableStealthMode = true;
    };
  };

  services.openssh = {
    enable = true;
    extraConfig = ''
      PubkeyAuthentication yes
      AuthenticationMethods publickey
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PermitRootLogin no
      X11Forwarding no
      AllowAgentForwarding no
      AllowTcpForwarding local
      GatewayPorts no
      PermitTunnel no
      AllowUsers ${username}
      ClientAliveInterval 60
      ClientAliveCountMax 3
    '';
  };

  users.users.${username}.openssh.authorizedKeys.keyFiles = [
    ../keys/gachikuku-id-ed25519.pub
  ];

  power = {
    restartAfterPowerFailure = true;
    restartAfterFreeze = true;
    sleep = {
      computer = "never";
      display = "never";
      harddisk = "never";
      allowSleepByPowerButton = false;
    };
  };

  system.defaults = {
    SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false;
    loginwindow.GuestEnabled = false;
    CustomUserPreferences = {
      "com.apple.screensaver" = {
        idleTime = 0;
        askForPassword = 0;
        askForPasswordDelay = 2147483647;
      };
      NSGlobalDomain."com.apple.autologout.AutoLogOutDelay" = 0;
    };
    NSGlobalDomain = {
      AppleICUForce24HourTime = true;
      AppleShowAllExtensions = true;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
    };
  };

  environment.systemPackages = with pkgs; [
    cacert
    codex
    coreutils
    fd
    ffmpeg
    frida-tools
    gh
    git
    gnupg
    gopass
    gopass-jsonapi
    ideviceinstaller
    jq
    libimobiledevice
    llvm
    mitmproxy
    neovim
    nodejs_24
    pinentry_mac
    pi-coding-agent
    python313
    radare2
    ripgrep
    socat
    stow
    tailscale
    tmux
    tree-sitter
    usbmuxd
    uv
  ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "@admin" ];
  };
}
