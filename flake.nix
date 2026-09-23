{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nixpkgs-unstable, sops-nix, ... }:
    let system = "x86_64-linux";
    in {
      nixosConfigurations.infra = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          sops-nix.nixosModules.sops
          ./nixos/configuration.nix
          {
            nixpkgs.overlays = [
              (_: _: { inherit (nixpkgs-unstable.legacyPackages.${system}) talosctl; })
            ];

            nix.channel.enable = false;
            nix.registry.nixpkgs.flake = nixpkgs;
            nix.nixPath = [ "nixpkgs=${nixpkgs}" ];
          }
        ];
      };
    };
}

