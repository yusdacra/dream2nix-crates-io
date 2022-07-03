{
  description = "crates.io indexed & translated into dream2nix lockfile.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    dream2nix = {
      url = "github:nix-community/dream2nix/feat/indexers";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inp:
    inp.dream2nix.lib.makeFlakeOutputsForIndexes {
      source = ./.;
      systems = ["x86_64-linux"];
      indexNames = ["crates-io"];
      overrideOutputs = {
        mkIndexApp,
        prevOutputs,
        ...
      }: {
        apps =
          prevOutputs.apps
          // {
            index-crates-io-top-500-downloads = mkIndexApp {
              name = "crates-io";
              indexerName = "crates-io-simple";
              input = {
                maxPages = 5;
                sortBy = "downloads";
              };
            };
          };
      };
    };
}
