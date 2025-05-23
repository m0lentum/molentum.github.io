{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, ... }@inputs:
    inputs.flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import inputs.nixpkgs {
          inherit system;
        };
      in
      {
        devShells.default =
          pkgs.mkShell {
            buildInputs = [
              pkgs.just
              pkgs.entr
              pkgs.nodejs
              pkgs.nodePackages.katex
              pkgs.zola
            ];
          };
      });
}
