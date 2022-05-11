{
  description = "crates.io indexed & translated into dream2nix lockfile.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    dream2nix = {
      url = "github:yusdacra/dream2nix/feat/cargo-toml-translator";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ilib = {
      url = "github:yusdacra/dream2nix-index-lib";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.dream2nix.follows = "dream2nix";
    };
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
      d2n = dream2nix.lib.init {
        systems = [system];
        config.projectRoot = ./.;
      };
      ilib = inputs.ilib.lib.mkLib {
        inherit system;
        subsystem = "rust";
        fetcherName = "crates-io";
        translatorForPath = {
          "Cargo.lock" = "cargo-lock";
          __default = "cargo-toml";
        };
      };

      genTree = dream2nix.lib.dlib.prepareSourceTree {source = ./gen;};

      index = genTree.files."index.json".jsonContent;
      fetchedIndex = ilib.fetchIndex index;
      translatedIndex = ilib.translateIndex fetchedIndex;

      crates =
        (d2n.makeFlakeOutputs {
          source = ./crates;
          packageOverrides = {
            indexer.add-openssl.overrideAttrs = old: {
              buildInputs = (old.buildInputs or []) ++ [pkgs.openssl];
              nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.pkg-config];
              doCheck = false;
            };
          };
        })
        .packages
        .${system};

      mkIndexApp = args: let
        defaultSettings = {
          max_pages = 1;
          sort_by = "downloads";
          verbose = false;
          modifications = {
            additions = [];
            exclusions = [];
          };
        };
        settings = defaultSettings // args;
        script = pkgs.writeScript "index" ''
          #!${pkgs.stdenv.shell}
          ${crates.indexer}/bin/indexer '${builtins.toJSON settings}' > gen/index.json
        '';
      in {
        type = "app";
        program = toString script;
      };

      translateScript = let
        pkgsUnflattened =
          l.mapAttrsToList
          (
            name: versions:
              l.mapAttrsToList
              (version: hash: {inherit name version hash;})
              versions
          )
          index;
      in
        ilib.translateBin (l.flatten pkgsUnflattened);

      lockOutputs = ilib.mkLocksOutputs {tree = genTree;};
    in {
      hydraJobs = l.mapAttrs (_: pkg: {${system} = pkg;}) lockOutputs;
      packages.${system} = lockOutputs // crates;
      apps.${system} = {
        index-top-5k-downloads = mkIndexApp {
          max_pages = 50;
          sort_by = "downloads";
        };
        index-top-1k-downloads = mkIndexApp {
          max_pages = 10;
          sort_by = "downloads";
        };
        index-top-500-downloads = mkIndexApp {
          max_pages = 5;
          sort_by = "downloads";
        };
        index-top-100-downloads = mkIndexApp {
          max_pages = 1;
          sort_by = "downloads";
        };
        index-top-100-new = mkIndexApp {
          max_pages = 1;
          sort_by = "new";
        };
        index-top-100-recently-updated = mkIndexApp {
          max_pages = 1;
          sort_by = "recent-updates";
        };
        translate = {
          type = "app";
          program = toString translateScript;
        };
      };
      devShells.${system} = {
        indexer = with pkgs;
          mkShell {
            name = "indexer-devshell";
            buildInputs = [openssl];
            nativeBuildInputs = [pkg-config cargo rustfmt];
          };
      };
      lib.${system} = {
        inherit
          ilib
          index
          fetchedIndex
          translatedIndex
          translateScript
          ;
      };
    };
  in
    l.foldl'
    (acc: el: l.recursiveUpdate acc el)
    {}
    (l.map mkOutputsForSystem systems);
}
