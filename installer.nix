{ config, pkgs, lib, self, inputs, ... }:

# Installer USB for runabout. Built with:
#
#   nix build .#installer-iso
#   sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress conv=fsync
#
# On boot it logs in on tty1 and starts `runabout-install`, which asks
# which disk to use, makes you type YES, asks for a LUKS passphrase, then
# runs disko-install: partition (disko.nix) → format → install → boot
# entry. Everything runabout needs is baked into the ISO, so no network
# is required. Ctrl-C at any prompt drops you to a normal shell.

let
  system = pkgs.stdenv.hostPlatform.system;
  target = self.nixosConfigurations.runabout;

  # Every flake input (and their inputs), so the flake evaluates offline.
  flakeOutPaths =
    let
      collector = parent:
        map (child:
          [ child.outPath ]
          ++ (if child ? inputs && child.inputs != { } then collector child else [ ])
        ) (lib.attrValues parent.inputs);
    in
    lib.unique (lib.flatten (collector self));

  # Everything disko-install needs to evaluate + install runabout offline
  # (pattern from disko's docs/disko-install.md).
  dependencies = [
    target.config.system.build.toplevel
    target.config.system.build.diskoScript
    target.config.system.build.diskoScript.drvPath
    target.pkgs.stdenv.drvPath
    # needed by nixos' top-level activation build
    target.pkgs.perlPackages.ConfigIniFiles
    target.pkgs.perlPackages.FileSlurp
    (target.pkgs.closureInfo { rootPaths = [ ]; }).drvPath
  ] ++ flakeOutPaths;

  closureInfo = pkgs.closureInfo { rootPaths = dependencies; };

  # ships both `disko` and `disko-install`
  disko = inputs.disko.packages.${system}.disko;

  runabout-install = pkgs.writeShellApplication {
    name = "runabout-install";
    runtimeInputs = [ disko pkgs.util-linux pkgs.coreutils pkgs.systemd ];
    text = ''
      if [[ $EUID -ne 0 ]]; then
        exec sudo "$0" "$@"
      fi

      KEY=/tmp/secret.key            # must match passwordFile in disko.nix
      trap 'shred -u "$KEY" 2>/dev/null || true' EXIT

      echo
      echo "=== runabout installer (ThinkPad L460) ==="
      echo
      lsblk -d -o NAME,SIZE,MODEL,TRAN,TYPE | grep -v ' loop' || true
      echo

      read -rp "Install to which disk? [/dev/sda] " DISK
      DISK=''${DISK:-/dev/sda}
      if [[ ! -b $DISK ]]; then
        echo "error: $DISK is not a block device" >&2
        exit 1
      fi

      echo
      echo "!!! This ERASES EVERYTHING on $DISK:"
      lsblk -o NAME,SIZE,FSTYPE,LABEL "$DISK"
      echo
      read -rp "Type YES (capitals) to wipe $DISK and install runabout: " CONFIRM
      if [[ $CONFIRM != YES ]]; then
        echo "aborted — nothing was touched."
        exit 1
      fi

      while true; do
        read -rsp "LUKS passphrase: " P1; echo
        read -rsp "Repeat passphrase: " P2; echo
        if [[ -z $P1 ]]; then
          echo "passphrase can't be empty"
        elif [[ $P1 != "$P2" ]]; then
          echo "passphrases don't match, try again"
        else
          break
        fi
      done
      ( umask 077; printf '%s' "$P1" > "$KEY" )
      unset P1 P2

      disko-install \
        --flake "${self}#runabout" \
        --disk main "$DISK" \
        --write-efi-boot-entries

      echo
      echo "=== done ==="
      echo "Remove the USB stick and reboot. Unlock with your passphrase,"
      echo "log in as bryan / changeme, and run 'passwd' straight away."
      read -rp "Reboot now? [y/N] " R
      if [[ $R == [yY] ]]; then systemctl reboot; fi
    '';
  };
in
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = [
    runabout-install
    disko
  ];

  # Pulls runabout's whole closure (and the flake inputs) into the ISO.
  environment.etc."install-closure".source = "${closureInfo}/store-paths";

  # Faster to build than the default xz; the ISO is a bit bigger.
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";

  # Start the installer automatically on tty1, once per boot.
  programs.bash.loginShellInit = ''
    if [ "$(tty)" = /dev/tty1 ] && [ ! -e /tmp/.runabout-install-offered ]; then
      touch /tmp/.runabout-install-offered
      runabout-install || echo "(installer exited — run 'runabout-install' to try again)"
    fi
  '';

  services.getty.helpLine = lib.mkAfter ''

    runabout installer: run `runabout-install` (starts automatically on tty1).
  '';
}
