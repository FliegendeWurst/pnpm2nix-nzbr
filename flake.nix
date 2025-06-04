{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    ,
    }:
    flake-utils.lib.eachDefaultSystem
      (system:
      let
        pkgs = nixpkgs.legacyPackages.${system}.appendOverlays [
          self.overlays.default
        ];
      in
      {
        packages = {
          inherit (pkgs) mkPnpmPackage;
          example = pkgs.callPackage ./example { };
        };

        checks = {
          # TODO: migrate to nixpkgs-style nixfmt
          nixpkgs-fmt = pkgs.runCommand "check-nixpkgs-fmt" { nativeBuildInputs = [ pkgs.nixpkgs-fmt ]; } ''
            nixpkgs-fmt --check ${./.}
            touch $out
          '';

          build-example = self.packages.${system}.example;
        };
      })
    // {
      overlays.default = final: prev: {
        inherit (prev.callPackage ./derivation.nix { }) mkPnpmPackage;
      };
    };
}
