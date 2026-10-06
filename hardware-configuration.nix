# Hardware config for runabout — Lenovo ThinkPad L460.
#
# Filesystems, swap and the LUKS device are NOT here: disko.nix declares
# them and NixOS generates the matching fileSystems entries. This is the
# equivalent of:
#
#   nixos-generate-config --no-filesystems --show-hardware-config
#
# Re-run that on the laptop if you ever want to double-check the module list.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [
    "xhci_pci" "ahci" "usb_storage" "sd_mod" "rtsx_pci_sdmmc"
    "aesni_intel" "cryptd"       # fast LUKS unlock in the initrd
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
