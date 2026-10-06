{ ... }:

# runabout's disk layout, declared once. disko uses this to partition
# and format during install, and NixOS uses it to generate fileSystems,
# swap and the LUKS unlock at boot — so hardware-configuration.nix no
# longer carries any disk UUIDs.
#
#   GPT
#   ├── ESP   2 GiB  vfat   → /bios   (systemd-boot keeps kernels here)
#   └── luks  rest   LUKS2 "cryptroot"
#       └── btrfs
#           ├── @      → /
#           ├── @home  → /home
#           ├── @nix   → /nix
#           ├── @log   → /var/log
#           └── @swap  → /.swapvol   (8 GiB swapfile, no CoW)
#
# `device` is only the default — the installer passes the real disk
# with `--disk main /dev/whatever`.

let
  btrfsOpts = [ "compress=zstd" "noatime" ];
in
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "2G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/bios";
            mountOptions = [ "fmask=0077" "dmask=0077" ];
          };
        };

        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            # Only read while formatting (the installer writes your
            # passphrase here, then shreds it). Not used at boot —
            # you type the passphrase at the prompt.
            passwordFile = "/tmp/secret.key";
            settings.allowDiscards = true;   # lets fstrim reach the SSD
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "@"     = { mountpoint = "/";        mountOptions = btrfsOpts; };
                "@home" = { mountpoint = "/home";    mountOptions = btrfsOpts; };
                "@nix"  = { mountpoint = "/nix";     mountOptions = btrfsOpts; };
                "@log"  = { mountpoint = "/var/log"; mountOptions = btrfsOpts; };
                # Separate subvolume so snapshots of @ never include swap.
                # Raise to >= RAM size if you want hibernation.
                "@swap" = {
                  mountpoint = "/.swapvol";
                  swap.swapfile.size = "8G";
                };
              };
            };
          };
        };
      };
    };
  };
}
