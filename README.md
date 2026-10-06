```
                            ______              _____ 
___________  ______________ ___  /___________  ___  /_
__  ___/  / / /_  __ \  __ `/_  __ \  __ \  / / /  __/
_  /   / /_/ /_  / / / /_/ /_  /_/ / /_/ / /_/ // /_  
/_/    \__,_/ /_/ /_/\__,_/ /_.___/\____/\__,_/ \__/

```

## changelog
* **runabout installer**: +`disko.nix` (LUKS2 + btrfs subvolumes), +`installer.nix` offline install USB
* **runabout port**: forked from `uss-enterprise` for the ThinkPad L460 — systemd-boot (ESP at `/bios`, 32 entries), Intel HD 520 VA-API, TLP/thermald, user `bryan`, Jellyfin/nginx off
* **26.11.20260919.20b1ddd**: +jogger
* **26.11.20260919.20b1ddd**: +firefox hw decoding, improved update script, fixed git pushes (lawl)
* **26.11.20260623.89570f2**: Now using NixOS system versioning, added git commits to `update.sh`
* **v.0.2.0**: NixOS `25.11` -> `26.11`, also nixpkg `stable` -> `unstable`
* **v.0.1.4**: +`home.nix`, +`networking.nix`
* **v.0.1.3**: +CUPS printing service, +`gnupg`
* **v.0.1.2**: +`host.nix` module
* **v.0.1.1**: +flake

## structure
```
/etc/nixos
.
├── configuration.nix   # top level config
├── disko.nix           # disk layout: ESP + LUKS + btrfs subvolumes
├── flake.lock
├── flake.nix
├── hardware-configuration.nix
├── home.nix            # user level config
├── installer.nix       # install USB (nix build .#installer-iso)
├── host.nix            # host level config
├── jogger              # my alias browser
│   ├── go.mod
│   ├── go.sum
│   ├── jogger
│   └── main.go
├── jogger.nix
├── networking.nix
├── packages.nix
├── README.md
├── services.nix
├── update.sh       # alias = update
└── zsh.nix

2 directories, 19 files
```

## specs
```
bryan@runabout
--------------
OS: 26.11 (Zokor) x86_64
Host: Lenovo ThinkPad L460
DE: KDE Plasma
WM: KWin (Wayland)
CPU: Intel Core i5-6200U @ 2.80 GHz
GPU: Intel HD Graphics 520 [Integrated]
Boot: systemd-boot (UEFI, ESP at /bios)
Disk: LUKS2 → btrfs (@ @home @nix @log @swap)
Swap: *50% zram + 8 GiB swapfile
```

## install (fresh, wipes the disk)
```sh
nix build .#installer-iso                     # from any x86_64 NixOS box
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress conv=fsync
```
Boot the L460 from the stick (F12) → pick disk → type `YES` → set LUKS
passphrase → reboot. First login: `bryan` / `changeme`, then `passwd`.

Over the network instead (L460 booted from any NixOS ISO, root password set):
```sh
echo -n 'passphrase' > /tmp/secret.key
nix run github:nix-community/nixos-anywhere -- \
  --disk-encryption-keys /tmp/secret.key /tmp/secret.key \
  --flake .#runabout root@<ip>
```

## TODO
* [x] ~~setup home-manager~~
* [x] ~~setup flake~~
* [ ] modularize *further*
    * [x] ~~host.nix~~
    * [x] ~~home.nix~~
    * [x] ~~networking.nix~~
    * [x] ~~services.nix~~
    * [ ] come up with more goals

