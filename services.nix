{ config, pkgs, lib, ... }:

let
  # Private (RFC1918) ranges allowed to reach sshd.
  # Tighten to your home subnet (e.g. "10.0.0.0/24") if you like.
  lanRanges = [ "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" ];
in
{
  ############################################################
  # Printing (CUPS)
  ############################################################
  services.printing = {
    enable = true;
    drivers = [ pkgs.brlaser pkgs.brgenml1lpr pkgs.brgenml1cupswrapper ];
    # ^ only needed as a fallback; try driverless first and you can drop these later
  };

  # mDNS / Bonjour so the printer is discoverable on the LAN
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    # Announce this box as runabout.local so `lanfind` (zsh.nix)
    # and `ssh runabout.local` can find it.
    publish = {
      enable = true;
      addresses = true;
    };
  };

  ############################################################
  # Sound (PipeWire)
  ############################################################
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    #jack.enable = true;
  };

  ############################################################
  # Bluetooth applet (hardware.bluetooth lives in host.nix)
  ############################################################
  services.blueman.enable = true;

  ############################################################
  # Jellyfin — OFF on runabout (uss-enterprise is the media
  # server). Flip `enable` if you want it here too; Intel QSV /
  # VA-API transcoding works via hardware.graphics (host.nix).
  ############################################################
  services.jellyfin = {
    enable = false;
    openFirewall = true;      # opens 8096 (http) and 8920 (https)
    user = "jellyfin";
    group = "jellyfin";
    # dataDir, cacheDir, configDir default under /var/lib/jellyfin
  };
  # users.users.jellyfin.extraGroups = [ "render" "video" ];  # for HW transcoding

  ############################################################
  # nginx — OFF on runabout. If enabled, also open 80/443 in
  # networking.nix. Reasonable hardened defaults otherwise.
  ############################################################
  services.nginx = {
    enable = false;
    recommendedGzipSettings  = true;
    recommendedOptimisation  = true;
    recommendedProxySettings = true;
    recommendedTlsSettings   = true;
    virtualHosts."localhost" = {
      root = "/var/www";
      locations."/" = {
        tryFiles = "$uri $uri/ /index.html";
      };
    };
    # Example reverse-proxy in front of Jellyfin. Uncomment
    # and edit the serverName when you're ready.
    #
    # virtualHosts."jellyfin.local" = {
    #   locations."/" = {
    #     proxyPass = "http://127.0.0.1:8096";
    #     proxyWebsockets = true;
    #   };
    # };
  };

  ############################################################
  # OpenSSH — LAN only, no root
  #
  # Two gates: the firewall only opens 22 to private ranges, and
  # sshd's AllowUsers only accepts `bryan` from those ranges.
  ############################################################
  services.openssh = {
    enable = true;
    openFirewall = false;              # opened to the LAN only, below
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = true;   # set false once you've added keys
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
      AllowUsers = map (net: "bryan@${net}") lanRanges;
    };
  };

  # -I (insert) rather than -A so the accepts land ahead of the
  # chain's final refuse rule. nixos-fw is flushed on every reload,
  # so these never pile up.
  networking.firewall.extraCommands = lib.concatMapStrings (net: ''
    iptables -I nixos-fw -p tcp --dport 22 -s ${net} -j nixos-fw-accept
  '') lanRanges;
}
