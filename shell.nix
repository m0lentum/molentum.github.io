{ sources ? import ./nix/sources.nix
, pkgs ? import sources.nixpkgs {}
}:

pkgs.mkShell {
  buildInputs = with pkgs; [
    niv
    just

    nodejs
    nodePackages.katex
    zola
  ];
}
