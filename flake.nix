{
  description = "crates.io indexed & translated into dream2nix lockfile.";

  inputs = {
    dream2nix = {
      url = "github:yusdacra/dream2nix/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nix-filter.url = "github:numtide/nix-filter";
  };

  outputs = {
    dream2nix,
    nixpkgs,
    nix-filter,
    ...
  } @ inputs: let
    lib = nixpkgs.lib;
    l = lib // builtins;
    systems = ["x86_64-linux"];

    mkOutputsForSystem = system: let
      pkgs = nixpkgs.legacyPackages.${system};
      d2n = dream2nix.lib.init {
        systems = [system];
        config.projectRoot = ./.;
      };

      callPackage = f: args:
        pkgs.callPackage f (args // {inherit dream2nix system lib;});

      fetcher = callPackage ./fetcher {};
      translator = callPackage ./translator {};
      dreamLockFor = name: version: let
        pkg = {inherit name version;};
        pkgWithSrc = pkg // {source = fetcher.fetch pkg;};
        dreamLock = translator.translate pkgWithSrc;
      in
        l.toJSON dreamLock;

      index = l.fromJSON (l.readFile ./index.json);
      fetchedIndex = fetcher.fetchIndex index;
      translatedIndex = translator.translateIndex fetchedIndex;

      outputs = d2n.makeFlakeOutputs {
        source = nix-filter.lib.filter {
          root = ./.;
          exclude = [
            "flake.nix"
            "index.json"
            "flake.lock"
            "README"
            "locks"
          ];
        };
        packageOverrides.indexer.add-openssl.overrideAttrs = old: {
          buildInputs = (old.buildInputs or []) ++ [pkgs.openssl];
          nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.pkg-config];
        };
      };

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
          ${outputs.packages.${system}.indexer}/bin/indexer '${builtins.toJSON settings}' > index.json
        '';
      in {
        type = "app";
        program = toString script;
      };

      lockOutputs = let
        pkgsNames = l.attrNames (l.readDir ./locks);
        pkgsUnfolded =
          l.map (
            name:
              l.genAttrs
              (
                l.map
                (version: "${name}-${version}")
                (l.attrNames (l.readDir "${./locks}/${name}"))
              )
              (
                n: let
                  version = l.removePrefix "${name}-" n;
                  outputs = dream2nix.lib.${system}.makeOutputsForDreamLock {
                    dreamLock = l.fromJSON (
                      l.readFile "${./locks}/${name}/${version}/dream-lock.json"
                    );
                  };
                in
                  outputs.packages.${name}
              )
          )
          pkgsNames;
      in
        l.foldl'
        (
          acc: el:
            acc
            // (
              l.mapAttrs' (
                n: v:
                  l.nameValuePair (l.replaceStrings ["."] ["_"] n) v
              )
              el
            )
        )
        {}
        pkgsUnfolded;
    in rec {
      packages.${system} = lockOutputs;
      apps.${system} = {
        index-top-5k-downloads = mkIndexApp {
          max_pages = 50;
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
          program = "${outputs.packages.${system}.translator}/bin/translator";
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
          };
      };
      lib.${system} = {
        inherit
          fetcher
          translator
          index
          fetchedIndex
          translatedIndex
          dreamLockFor
          ;
      };
    };
  in
    l.foldl'
    (acc: el: l.recursiveUpdate acc el)
    {}
    (l.map mkOutputsForSystem systems);
}
