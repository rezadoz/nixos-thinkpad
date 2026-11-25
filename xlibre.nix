{ inputs, ... }:

# XLibre — drop-in replacement for the X.Org server + drivers.
#
# The overlay (flake input `xlibre-nixos`) redirects `xorg-server` and the
# xf86-* driver attributes to XLibre builds, so the stock
# services.xserver module keeps working unchanged. Everything that runs an
# X server picks it up: SDDM's greeter, the bspwm session, Plasma (X11).
# The Plasma Wayland session is unaffected (it uses Xwayland, not this).
#
# Intel HD 520 uses `modesetting`, which is built into the XLibre server,
# and input goes through XLibre's xf86-input-libinput — so nothing else
# needs to change in host.nix.
#
# To go back to X.Org: drop ./xlibre.nix from configuration.nix (or
# boot the previous generation).
#
# Check it's live (from an X session):
#   X -version 2>&1 | head -3
#   grep -Ei 'XLibre|modesetting|libinput' /var/log/Xorg.0.log ~/.local/share/xorg/Xorg.0.log 2>/dev/null

{
  nixpkgs.overlays = [
    (import "${inputs.xlibre-nixos}/overlay.nix")
  ];
}
