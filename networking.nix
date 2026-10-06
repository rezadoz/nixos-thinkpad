{ config, pkgs, lib, ... }:

{
  ############################################################
  # Networking
  ############################################################
  networking = {
    hostName = "runabout";
    networkmanager.enable = true;

    useDHCP = lib.mkDefault true;

#     defaultGateway = "10.0.0.1";
#     nameservers = [ "1.1.1.1" "9.9.9.9" ];

    # runabout is a laptop that roams onto other people's networks,
    # so no routing/NAT and no world-open server ports here.
    nat.enable = false;

    firewall = {
      enable = true;
      # SSH (22) is opened to private ranges only — see services.nix.
      # If you turn nginx back on there, add 80/443 here.
      allowedTCPPorts = [ ];
      allowedUDPPorts = [ ];
    };
  };
}
