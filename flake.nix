{
  description = "A Nix-flake-based development environment";

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };
  };

  outputs = { self, nixpkgs, ... }: let
    supportedSystems = nixpkgs.lib.systems.flakeExposed;

    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

    pkgs = forAllSystems (system: nixpkgs.legacyPackages.${system});

    installNixPackages = pkgs: [
      pkgs.oras
      
      pkgs.jq
      pkgs.semver-tool
      pkgs.busybox
    ];

    installNixProfilePackages = pkgs: [
      pkgs.nixd # Nix Language Server
      pkgs.nixfmt-rfc-style # Nix Formatter
    ];

    installNixShellScripts = pkgs : [
      (
        pkgs.writeShellScriptBin "log" ''
          echo
          ${pkgs.gum}/bin/gum log --level $1 "$2 ..."
          echo
        ''
      )
    ];
  in
  {
    # Run: $ nix develop
    devShells = forAllSystems (system: {
      default = pkgs.${system}.mkShellNoCC {
        packages = (installNixPackages pkgs.${system}) ++ (installNixShellScripts pkgs.${system});
      };
    });

    # Run: $ nix profile install
    packages = forAllSystems (system: {
      default = pkgs.${system}.buildEnv {
        name = "profile";
        paths = (installNixPackages pkgs.${system}) ++ (installNixProfilePackages pkgs.${system});
      };
    });
  };
}
