{ config, pkgs, lib, ... }:

# bspwm session config for `bryan` (home-manager).
# The session itself is registered system-side in bspwm.nix; SDDM starts
# sxhkd + bspwm, which read the files written here:
#   ~/.config/bspwm/bspwmrc    ~/.config/sxhkd/sxhkdrc    ~/.config/polybar/config.ini
#
# Session daemons are started from bspwmrc by store path rather than via
# home-manager services, so none of them leak into the Plasma session
# (dunst vs. Plasma notifications, a second panel, a second locker...).
#
# Reload after a rebuild: super + alt + r (bspwm), super + Escape (sxhkd).

let
  terminal = "alacritty";

  # Gruvbox-ish palette shared by bspwm borders and polybar
  c = {
    bg      = "#1d2021";
    bgAlt   = "#3c3836";
    fg      = "#ebdbb2";
    dim     = "#928374";
    accent  = "#d79921";
    urgent  = "#cc241d";
  };

  polybar = pkgs.polybar.override { pulseSupport = true; };

  # Daemons started once per session. `bspc wm -r` re-runs bspwmrc, so each
  # is guarded by its full store path to avoid duplicates on reload.
  daemons = [
    "${pkgs.picom}/bin/picom --backend glx --vsync"
    "${pkgs.dunst}/bin/dunst"
    "${polybar}/bin/polybar main"
    "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
    "${pkgs.networkmanagerapplet}/bin/nm-applet"
    "${pkgs.blueman}/bin/blueman-applet"
    # lock on `loginctl lock-session` and before suspend
    "${pkgs.xss-lock}/bin/xss-lock --transfer-sleep-lock -- i3lock -n -c ${lib.removePrefix "#" c.bg}"
  ];
in
{
  ############################################################
  # bspwm
  ############################################################
  xsession.windowManager.bspwm = {
    enable = true;

    # "focused" = the laptop panel at login. Hotplugged monitors get
    # bspwm's default single desktop; manage those with arandr/xrandr.
    monitors.focused = [ "1" "2" "3" "4" "5" "6" "7" "8" "9" "10" ];

    settings = {
      border_width = 2;
      window_gap = 8;
      split_ratio = 0.52;
      borderless_monocle = true;
      gapless_monocle = true;
      single_monocle = false;
      focus_follows_pointer = true;
      pointer_modifier = "mod4";       # super + drag = move, super + right-drag = resize
      normal_border_color = c.bgAlt;
      active_border_color = c.bgAlt;
      focused_border_color = c.accent;
      presel_feedback_color = c.accent;
    };

    rules = {
      "Pavucontrol"        = { state = "floating"; };
      ".blueman-manager-wrapped" = { state = "floating"; };
      "Blueman-manager"    = { state = "floating"; };
      "Nm-connection-editor" = { state = "floating"; };
      "Arandr"             = { state = "floating"; };
      "Yad"                = { state = "floating"; };
      "Zathura"            = { state = "tiled"; };
      "mpv"                = { state = "floating"; center = true; };
    };

    extraConfig = ''
      # plain arrow cursor on the root window instead of the X "×"
      ${pkgs.xsetroot}/bin/xsetroot -cursor_name left_ptr

      # wallpaper: drop an image at ~/.config/wallpaper, else solid colour
      if [ -f "$HOME/.config/wallpaper" ]; then
        ${pkgs.feh}/bin/feh --no-fehbg --bg-fill "$HOME/.config/wallpaper"
      else
        ${pkgs.xsetroot}/bin/xsetroot -solid '${c.bg}'
      fi

      run_once() {
        ${pkgs.procps}/bin/pgrep -u "$(id -u)" -f -- "$1" >/dev/null || "$@" &
      }
      ${lib.concatMapStringsSep "\n" (d: "run_once ${d}") daemons}
    '';
  };

  ############################################################
  # sxhkd — keybindings (super = the Windows key)
  ############################################################
  services.sxhkd = {
    enable = true;
    keybindings = {
      # --- apps ---
      "super + Return"          = terminal;
      "super + space"           = "rofi -show drun -show-icons";
      "super + shift + space"   = "rofi -show run";
      "super + Tab"             = "rofi -show window";
      "super + e"               = "dolphin";
      "super + b"               = "firefox";

      # --- session ---
      "super + Escape"          = "pkill -USR1 -x sxhkd";        # reload keys
      "super + alt + r"         = "bspc wm -r";                   # reload bspwm
      "super + alt + q"         = "bspc quit";                    # log out
      "super + x"               = "loginctl lock-session";        # lock (xss-lock → i3lock)

      # --- windows ---
      "super + {_,shift + }w"   = "bspc node -{c,k}";             # close / kill
      "super + m"               = "bspc desktop -l next";         # monocle toggle
      "super + {t,shift + t,s,f}" = "bspc node -t {tiled,pseudo_tiled,floating,fullscreen}";
      "super + g"               = "bspc node -s biggest.window";  # swap with biggest

      # focus / swap  (vim keys or arrows)
      "super + {_,shift + }{h,j,k,l}"           = "bspc node -{f,s} {west,south,north,east}";
      "super + {_,shift + }{Left,Down,Up,Right}" = "bspc node -{f,s} {west,south,north,east}";
      "super + {grave,apostrophe}"              = "bspc {node,desktop} -f last";
      "super + bracket{left,right}"             = "bspc desktop -f {prev,next}.local";

      # desktops: focus / send window
      "super + {_,shift + }{1-9,0}" = "bspc {desktop -f,node -d} '^{1-9,10}'";

      # preselect split direction, then open a window
      "super + ctrl + {h,j,k,l}" = "bspc node -p {west,south,north,east}";
      "super + ctrl + space"     = "bspc node -p cancel";

      # resize: expand / contract
      "super + alt + {h,j,k,l}"         = "bspc node -z {left -20 0,bottom 0 20,top 0 -20,right 20 0}";
      "super + alt + shift + {h,j,k,l}" = "bspc node -z {right -20 0,top 0 20,bottom 0 -20,left 20 0}";

      # --- ThinkPad function keys ---
      "XF86AudioRaiseVolume"  = "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+";
      "XF86AudioLowerVolume"  = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
      "XF86AudioMute"         = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
      "XF86AudioMicMute"      = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
      "XF86MonBrightnessUp"   = "brightnessctl set 5%+";
      "XF86MonBrightnessDown" = "brightnessctl set 5%-";

      # --- screenshots ---
      "Print"         = "maim -s | xclip -selection clipboard -t image/png";   # region → clipboard
      "shift + Print" = "mkdir -p ~/Pictures/screenshots && maim ~/Pictures/screenshots/$(date +%F_%H-%M-%S).png";
    };
  };

  ############################################################
  # polybar — started from bspwmrc as `polybar main`
  ############################################################
  xdg.configFile."polybar/config.ini".text = ''
    [colors]
    bg = ${c.bg}
    bg-alt = ${c.bgAlt}
    fg = ${c.fg}
    dim = ${c.dim}
    accent = ${c.accent}
    urgent = ${c.urgent}

    [bar/main]
    width = 100%
    height = 22
    background = ''${colors.bg}
    foreground = ''${colors.fg}
    padding-right = 1
    module-margin = 1
    separator = |
    separator-foreground = ''${colors.dim}
    font-0 = JetBrainsMono Nerd Font:size=9;2
    modules-left = bspwm
    modules-center = xwindow
    modules-right = wlan cpu memory pulseaudio battery date tray
    wm-restack = bspwm
    enable-ipc = true

    [module/bspwm]
    type = internal/bspwm
    pin-workspaces = true
    label-focused = %name%
    label-focused-background = ''${colors.bg-alt}
    label-focused-underline = ''${colors.accent}
    label-focused-padding = 1
    label-occupied = %name%
    label-occupied-padding = 1
    label-urgent = %name%
    label-urgent-background = ''${colors.urgent}
    label-urgent-padding = 1
    label-empty =
    label-monocle = [M]
    label-floating = [F]

    [module/xwindow]
    type = internal/xwindow
    label = %title:0:60:...%

    [module/wlan]
    type = internal/network
    interface-type = wireless
    interval = 5
    label-connected = 󰖩 %essid%
    label-disconnected = 󰖪
    label-disconnected-foreground = ''${colors.dim}

    [module/cpu]
    type = internal/cpu
    interval = 2
    label = 󰻠 %percentage:2%%

    [module/memory]
    type = internal/memory
    interval = 3
    label = 󰍛 %percentage_used:2%%

    [module/pulseaudio]
    type = internal/pulseaudio
    use-ui-max = false
    format-volume = <label-volume>
    label-volume = 󰕾 %percentage%%
    label-muted = 󰝟 muted
    label-muted-foreground = ''${colors.dim}
    click-right = pavucontrol

    [module/battery]
    type = internal/battery
    battery = BAT0
    adapter = AC
    full-at = 99
    poll-interval = 10
    label-charging = 󰂄 %percentage%%
    label-discharging = 󰁹 %percentage%%
    label-full = 󰁹 full

    [module/date]
    type = internal/date
    interval = 5
    date = %a %b %d
    time = %H:%M
    label = %date% %time%
    label-foreground = ''${colors.accent}

    [module/tray]
    type = internal/tray
    tray-spacing = 4px
  '';

  ############################################################
  # Small bits the session needs
  ############################################################
  # dunst is started from bspwmrc (see header); this is just its look
  xdg.configFile."dunst/dunstrc".text = ''
    [global]
    font = JetBrainsMono Nerd Font 9
    origin = top-right
    offset = 10x32
    frame_width = 2
    frame_color = "${c.accent}"
    background = "${c.bg}"
    foreground = "${c.fg}"
    corner_radius = 0

    [urgency_critical]
    frame_color = "${c.urgent}"
  '';
}
