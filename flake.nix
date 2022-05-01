{
  description = "crates.io indexed & translated into dream2nix lockfile.";

  inputs = {
    dream2nix = {
      url = "github:nix-community/dream2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = {
    dream2nix,
    nixpkgs,
    ...
  } @ inputs: let
    l = nixpkgs.lib // builtins;
    systems = ["x86_64-linux"];

    mkOutputsForSystem = system: let
      pkgs = nixpkgs.legacyPackages.${system};
      dream2nix = inputs.dream2nix.lib.init {
        systems = [system];
        config.projectRoot = ./.;
      };

      indexerOutputs = dream2nix.makeFlakeOutputs {
        source = ./indexer;
        packageOverrides.indexer.add-openssl.overrideAttrs = old: {
          buildInputs = (old.buildInputs or []) ++ [pkgs.openssl];
          nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.pkg-config];
        };
      };

      mkIndexApp = settings: let
        script = pkgs.writeScript "index" ''
          #!${pkgs.stdenv.shell}
          ${indexerOutputs.packages.${system}.indexer}/bin/indexer '${builtins.toJSON settings}' > index.json
        '';
      in {
        type = "app";
        program = toString script;
      };
    in rec {
      packages = indexerOutputs.packages;
      apps.${system} = {
        index-top-5k-downloads = mkIndexApp {max_pages = 50; sort_by = "downloads";};
        index-top-100-new = mkIndexApp {max_pages = 1; sort_by = "new";};
        index-top-100-recently-updated = mkIndexApp {max_pages = 1; sort_by = "recent-updates";};
      };
      devShells.${system} = {
        indexer = with pkgs;
          mkShell {
            name = "indexer-devshell";
            buildInputs = [openssl];
            nativeBuildInputs = [pkg-config cargo rustfmt];
          };
      };
    };
  in
    l.foldl'
    (acc: el: l.recursiveUpdate acc el)
    {}
    (l.map mkOutputsForSystem systems);
}
