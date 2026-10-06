{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ./disko.nix               # disk layout: LUKS + btrfs (needs the disko module, see flake.nix)
      ./host.nix
      ./networking.nix
      ./packages.nix
      ./services.nix
    ];

  # runabout boots UEFI + systemd-boot, with the ESP mounted at /bios
  # (not /boot). disko.nix declares the /bios filesystem.
  # systemd-boot keeps every entry's kernel + initrd ON the ESP, so the
  # entry cap below is what keeps /bios from filling up.
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 32;
  };
  boot.loader.efi = {
    canTouchEfiVariables = true;
    efiSysMountPoint = "/bios";
  };
  boot.kernelPackages = pkgs.linuxPackages_latest;
#  boot.kernelPackages = pkgs.linuxPackages_6_6;

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Desktop (display stack stays here; daemons live in services.nix)
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  users.users.bryan = {
    isNormalUser = true;
    description = "bryan";
    extraGroups = [ "networkmanager" "wheel" "video" ];
    shell = pkgs.zsh;              # zsh itself is configured by home-manager (zsh.nix)
    # Only applies when the user is first created (i.e. a fresh install).
    # Run `passwd` right after first login.
    initialPassword = "changeme";
    packages = with pkgs; [
      kdePackages.kate
    #  thunderbird
    ];
  };
  programs.zsh.enable = true;      # system side: needed for a zsh login shell

  # home-manager: user config lives in home.nix (which imports zsh.nix)
  home-manager.users.bryan = import ./home.nix;

  # Hardware video decoding — Intel HD 520 (Skylake) via VA-API.
  # The VA-API driver itself (intel-media-driver) is set up in host.nix.
  programs.firefox = {
    enable = true;
    preferences = {
      "media.ffmpeg.vaapi.enabled" = true;
      "media.hardware-video-decoding.force-enabled" = true;
      "media.av1.enabled" = false;   # Skylake has no AV1 decode
    };
  };

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";     # intel-media-driver (Broadwell and newer)
  }; # /hardware decoding

  programs.nix-ld.enable = true;
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };

  programs.kdeconnect.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    git
    vim
  #  wget
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # runabout was installed on 26.05 — this must match ITS original install,
  # not uss-enterprise's. Check the old runabout config before switching.
  system.stateVersion = "26.05"; # DO NOT EDIT

}
