{
  description = "WildFly 41.0.1.Final on JDK 21 for NixOS";

  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.zst";

  outputs = { self, nixpkgs }: {
    packages = builtins.mapAttrs (system: pkgs: {
      wildfly = pkgs.callPackage ./pkgs/wildfly/package.nix { };

      default = self.packages.${system}.wildfly;
    }) nixpkgs.legacyPackages;

    overlays.default = final: prev: {
      wildfly = final.callPackage ./pkgs/wildfly/package.nix { };
    };

    nixosModules.wildfly = import ./modules/wildfly.nix;
    nixosModules.default = self.nixosModules.wildfly;

    checks = builtins.mapAttrs (system: pkgs: {
      default = import ./tests/default.nix { inherit pkgs; };
    }) nixpkgs.legacyPackages;
  };
}
