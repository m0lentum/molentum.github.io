{ pkgs ? import (fetchTarball {
  # nixos-20.03
  url = "https://github.com/NixOS/nixpkgs-channels/archive/ab3adfe1c769c22b6629e59ea0ef88ec8ee4563f.tar.gz";
  sha256 = "1m4wvrrcvif198ssqbdw897c8h84l0cy7q75lyfzdsz9khm1y2n1";
}) {}
}:

let
  jekyll_env = pkgs.bundlerEnv {
    name = "jekyll_env";
    gemdir = ./.;
  };
in
pkgs.mkShell {
  buildInputs = [ jekyll_env ];
}
