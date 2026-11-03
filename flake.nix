{
  description = "WildFly 42.0.0.Final on JDK 21 for NixOS";

  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.zst";

  outputs = { self, nixpkgs }: {
    packages = builtins.mapAttrs (system: pkgs:
      let
        wildfly = pkgs.callPackage ./pkgs/wildfly/package.nix { };
        wildfly-bin = pkgs.callPackage ./pkgs/wildfly-bin/package.nix { };
      in {
        inherit wildfly wildfly-bin;
        default = wildfly;
      }) nixpkgs.legacyPackages;

    overlays.default = final: prev: {
      wildfly = final.callPackage ./pkgs/wildfly/package.nix { };
      wildfly-bin = final.callPackage ./pkgs/wildfly-bin/package.nix { };
    };

    nixosModules.wildfly = import ./modules/wildfly.nix;
    nixosModules.default = self.nixosModules.wildfly;

    checks = builtins.mapAttrs (system: pkgs: {
      default = import ./tests/default.nix { inherit pkgs; };
      wildfly-bin-binary =
        let bin = pkgs.callPackage ./pkgs/wildfly-bin/package.nix { };
        in pkgs.runCommand "wildfly-bin-binary" { } ''
          test -x ${bin}/bin/wildfly
          touch $out
        '';
    }) nixpkgs.legacyPackages;
  };
}
