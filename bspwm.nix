{ config, pkgs, ... }:

# bspwm — tiling WM as an extra X11 session next to Plasma.
# Pick "bspwm" from the session menu in SDDM. Plasma stays the default.
#
# This file is the system side: the session entry and a handful of tools.
# The actual config (bspwmrc, sxhkdrc, polybar) is per-user and lives in
# bspwm-home.nix (home-manager), which bspwm/sxhkd read from ~/.config.

{
  services.xserver.windowManager.bspwm.enable = true;
  # (services.xserver.enable + SDDM are already on in configuration.nix)

  # Screen locker: enabling the module installs i3lock *and* sets up its
  # PAM service so your password actually unlocks it. xss-lock is started
  # from bspwmrc (not programs.xss-lock, which would also run in Plasma).
  programs.i3lock.enable = true;

  environment.systemPackages = with pkgs; [
    alacritty         # terminal       (super + Return)
    rofi              # launcher       (super + space)
    pavucontrol       # audio mixer GUI
    brightnessctl     # backlight keys (bryan is already in `video`)
    maim xclip        # screenshots    (Print / shift + Print)
    xdotool
    xsel
    xsetroot
    xrandr
    arandr            # GUI for xrandr / external monitors
    networkmanagerapplet  # nm-applet + nm-connection-editor
  ];
}
