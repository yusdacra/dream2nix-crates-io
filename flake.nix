{
  description = "crates.io indexed & translated into dream2nix lockfile.";

  inputs = {
    dream2nix = {
      url = "github:nix-community/dream2nix/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    slib = {
      url = "path:./lib";
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
      slib = inputs.slib.lib.mkLibForSystem system;

      pkgs = nixpkgs.legacyPackages.${system};
      d2n = dream2nix.lib.init {
        systems = [system];
        config.projectRoot = ./.;
      };

      index = l.fromJSON (l.readFile ./gen/index.json);
      fetchedIndex = slib.fetchIndex index;
      translatedIndex = slib.translateIndex fetchedIndex;

      crates =
        (d2n.makeFlakeOutputs {
          source = ./crates;
          packageOverrides = {
            indexer.add-openssl.overrideAttrs = old: {
              buildInputs = (old.buildInputs or []) ++ [pkgs.openssl];
              nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.pkg-config];
              doCheck = false;
            };
            translator.add-flake-src = {
              SLIB_FLAKE_SRC = toString inputs.slib;
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

      lockOutputs = let
        lockIndex = l.fromJSON (l.readFile ./gen/locks/index.json);
        sanitizePkgName = name: l.replaceStrings ["." "+"] ["_" "_"] name;
        mkPkg = name: version:
          (dream2nix.lib.${system}.makeOutputsForDreamLock {
            dreamLock = l.fromJSON (
              l.readFile "${./gen/locks}/${name}/${version}/dream-lock.json"
            );
          })
          .packages
          .${name};
        pkgs =
          l.mapAttrs
          (
            name: versions:
              l.listToAttrs (
                l.map (
                  version:
                    l.nameValuePair
                    (sanitizePkgName "${name}-${version}")
                    (mkPkg name version)
                )
                versions
              )
          )
          lockIndex;
      in
        l.foldl' (acc: el: acc // el) {} (l.attrValues pkgs);
    in rec {
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
          program = "${crates.translator}/bin/translator";
        };
      };
      devShells.${system} = {
        indexer = with pkgs;
          mkShell {
            name = "indexer-devshell";
            buildInputs = [openssl];
            nativeBuildInputs = [pkg-config cargo rustfmt];
          };
        translator = with pkgs;
          mkShell {
            name = "translator-devshell";
            nativeBuildInputs = [cargo rustfmt];
            SLIB_FLAKE_SRC = toString inputs.slib;
          };
      };
      lib.${system} = {
        inherit
          slib
          index
          fetchedIndex
          translatedIndex
          ;
      };
    };
  in
    l.foldl'
    (acc: el: l.recursiveUpdate acc el)
    {}
    (l.map mkOutputsForSystem systems);
}
