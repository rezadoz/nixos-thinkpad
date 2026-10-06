{
  description = "runabout (ThinkPad L460) NixOS configuration";

  inputs = {
    # Primary channel — now tracking the rolling unstable branch.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
#     nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Latest stable (26.05 "Yarara") kept available via an overlay as `pkgs.stable.*`.
    # Use this prefix when you want a package pinned to stable instead of unstable.
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";

    # home-manager that tracks nixpkgs *unstable* — this is the `master` branch.
    # (The `release-XX.YY` branches are for the matching *stable* nixpkgs.)
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative disk layout (disko.nix) — LUKS + btrfs subvolumes.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-stable, home-manager, disko, ... }@inputs:
    let
      system = "x86_64-linux";
    in {
      ##########################################################
      # The laptop itself
      ##########################################################
      nixosConfigurations.runabout = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          # Overlay that adds `pkgs.stable` (26.05) everywhere in the system
              ({ config, ... }: {
                nixpkgs.overlays = [
                  (final: prev: {
                    stable = import nixpkgs-stable {
                      inherit system;
                      config.allowUnfree = true;
                    };
                  })
                ];
                nixpkgs.config.android_sdk.accept_license = true;
              })

          disko.nixosModules.disko       # reads ./disko.nix (imported in configuration.nix)
          ./configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs   = true;
            home-manager.useUserPackages = true;
            # If HM would clobber an existing dotfile, back it up instead of erroring
            home-manager.backupFileExtension = "hm-bak";
            # Pass `inputs` down to home-manager modules if you ever need it there
            home-manager.extraSpecialArgs = { inherit inputs; };
          }
        ];
      };

      ##########################################################
      # Installer USB — boots, asks for a disk + LUKS passphrase,
      # then installs `runabout` above. Fully offline.
      #   nix build .#installer-iso
      ##########################################################
      nixosConfigurations.runabout-installer = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit self inputs; };
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ./installer.nix
        ];
      };

      packages.${system}.installer-iso =
        self.nixosConfigurations.runabout-installer.config.system.build.isoImage;
    };
}
