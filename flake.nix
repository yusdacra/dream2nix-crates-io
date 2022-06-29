{
  description = "crates.io indexed & translated into dream2nix lockfile.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    dream2nix = {
      url = "github:nix-community/dream2nix/feat/indexers";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ilib = {
      url = "github:yusdacra/dream2nix-index-lib/feat/d2n-apps";
      inputs.dream2nix.follows = "dream2nix";
    };
  };

  outputs = inp:
    inp.ilib.lib.makeOutputsForIndexes {
      source = ./.;
      indexesForSystems = {
        "x86_64-linux" = ["crates-io"];
      };
      extendOutputs = {
        system,
        mkIndexApp,
        ...
      }: prev: {
        apps.${system} =
          prev.apps.${system}
          // {
            index-crates-io-top-500-downloads = mkIndexApp {
              name = "crates-io";
              input = {
                max_pages = 5;
                sort_by = "downloads";
              };
            };
          };
      };
    };
}
