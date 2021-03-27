{ sources ? import ./nix/sources.nix }:

let
  pkgs = import sources.nixpkgs {};
  jekyll_env = pkgs.bundlerEnv {
    name = "jekyll_env";
    gemdir = ./.;
  };
in
pkgs.mkShell {
  buildInputs = [
    pkgs.niv
    jekyll_env
  ];
}
