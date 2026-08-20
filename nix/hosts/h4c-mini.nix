{ username, pkgs, fridaTools, ... }:
let
  appium = pkgs.callPackage ../pkgs/appium { };
  home = "/Users/${username}";

  appiumServer = pkgs.writeShellScript "h4c-appium-server" ''
    set -euo pipefail
    exec ${appium}/bin/appium server \
      --address 127.0.0.1 \
      --port 4723 \
      --base-path / \
      --use-drivers xcuitest \
      --log-level info \
      --log-no-colors \
      --log-timestamp
  '';

  remoteXpcTunnel = pkgs.writeShellScript "h4c-remotexpc-tunnel" ''
    set -euo pipefail
    exec ${appium}/bin/appium driver run xcuitest tunnel-creation -- \
      --tunnel-registry-port 42314 \
      --disconnect-retry-max-attempts 0 \
      --disconnect-retry-strategy exponential \
      --disconnect-retry-interval-ms 1000 \
      --disconnect-retry-backoff-max-interval-ms 30000
  '';
in
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

  # Explicit owner decision: this dedicated server prioritizes unattended
  # administration over privilege separation. Any process running as this user
  # can become root; keep SSH key-only and restrict network reachability.
  security.sudo.extraConfig = ''
    ${username} ALL=(ALL) NOPASSWD: ALL
  '';

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

  # The Appium server runs as a GUI LaunchAgent so Xcode code signing can use
  # the logged-in user's unlocked Keychain. RemoteXPC requires root and runs as
  # a boot LaunchDaemon. Both network listeners are restricted to loopback.
  launchd.user.agents.h4c-appium = {
    command = appiumServer;
    environment = {
      APPIUM_HOME = "${home}/.local/share/h4c-appium";
      APPIUM_XCUITEST_TUNNEL_REGISTRY_PORT = "42314";
      DEVELOPER_DIR = "/Applications/Xcode.app/Contents/Developer";
      HOME = home;
      PATH = "/usr/bin:/bin:/usr/sbin:/sbin";
    };
    serviceConfig = {
      RunAtLoad = true;
      KeepAlive = true;
      LimitLoadToSessionType = "Aqua";
      ProcessType = "Background";
      ThrottleInterval = 10;
      Umask = 63; # decimal representation of 077
      WorkingDirectory = home;
      StandardOutPath = "${home}/Library/Logs/h4c-appium.stdout.log";
      StandardErrorPath = "${home}/Library/Logs/h4c-appium.stderr.log";
    };
  };

  launchd.daemons.h4c-remotexpc = {
    command = remoteXpcTunnel;
    environment = {
      APPIUM_HOME = "/var/root/.local/share/h4c-appium";
      HOME = "/var/root";
      PATH = "/usr/bin:/bin:/usr/sbin:/sbin";
    };
    serviceConfig = {
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      LowPriorityIO = true;
      ThrottleInterval = 10;
      Umask = 63; # decimal representation of 077
      WorkingDirectory = "/var/root";
      StandardOutPath = "/var/root/Library/Logs/h4c-remotexpc.stdout.log";
      StandardErrorPath = "/var/root/Library/Logs/h4c-remotexpc.stderr.log";
    };
  };

  environment.systemPackages = with pkgs; [
    appium
    cacert
    codex
    coreutils
    fd
    ffmpeg
    fridaTools
    gh
    git
    gnupg
    gopass
    gopass-jsonapi
    ideviceinstaller
    jq
    libimobiledevice
    libusbmuxd
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
