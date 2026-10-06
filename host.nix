{ config, pkgs, lib, ... }:

# Host-level config for runabout — Lenovo ThinkPad L460
# (Intel Core i5-6200U "Skylake", Intel HD Graphics 520)

{
  ############################################################
  # Swap
  # zram first (fast compressed swap in RAM). The on-disk 8 GiB
  # swapfile behind it lives in its own @swap subvolume and is
  # declared in disko.nix.
  ############################################################
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;       # up to 50% of RAM as compressed swap
  };

  ############################################################
  # Bluetooth
  ############################################################
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;  # battery reporting, etc.
      };
    };
  };
  # (blueman applet is enabled in services.nix)

  ############################################################
  # Intel graphics (HD 520, Skylake / Gen9)
  # The kernel's modesetting driver is the default and the right
  # choice — no services.xserver.videoDrivers needed.
  ############################################################
  hardware.graphics = {
    enable = true;
    enable32Bit = true;       # for Steam / 32-bit games
    extraPackages = with pkgs; [
      intel-media-driver      # VA-API "iHD" — hardware video decode/encode
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [
      intel-media-driver
    ];
  };

  ############################################################
  # Laptop power management
  # Plasma 6 turns on power-profiles-daemon by default, which
  # conflicts with TLP — so it's explicitly switched off here.
  ############################################################
  services.power-profiles-daemon.enable = false;
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC  = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_AC  = "balance_performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "balance_power";

      # Battery care: uncomment to stop charging at 80% (good if
      # runabout lives on the charger). The L460 supports this
      # through the thinkpad_acpi driver.
      # START_CHARGE_THRESH_BAT0 = 75;
      # STOP_CHARGE_THRESH_BAT0  = 80;
    };
  };
  services.thermald.enable = true;   # Intel thermal daemon
  services.fstrim.enable = true;     # weekly TRIM for the SSD

  # btrfs: monthly scrub catches silent corruption early
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  # TrackPoint
  hardware.trackpoint = {
    enable = true;
    emulateWheel = true;      # middle-button + TrackPoint = scroll
  };

  ############################################################
  # Fonts
  ############################################################
  fonts = {
    #enableDefaultPackages = false;
    packages = with pkgs; [
      nerd-fonts.agave
      nerd-fonts.fira-code
      nerd-fonts.hack
      nerd-fonts.iosevka
      nerd-fonts.jetbrains-mono
      nerd-fonts.meslo-lg
      nerd-fonts.victor-mono
      nerd-fonts.zed-mono
      cozette
      dina-font
      liberation_ttf
      #noto-fonts   # I don't like their braille glyphs
      noto-fonts-color-emoji
    ];
    fontconfig = {
      enable = true;
      useEmbeddedBitmaps = true;   # for Firefox emoji rendering
    };
  };
}
