{
  dream2nix,
  lib,
  system,
  ...
}: let
  l = lib // builtins;

  fetchOutputs = dream2nix.lib.${system}.fetchers.fetchers.crates-io.outputs;
  # fetch one package.
  fetch = pkg: let
    outputs = fetchOutputs {
      pname = pkg.name;
      version = pkg.version;
    };
  in
    outputs.fetched (outputs.calcHash "sha256");

  # fetches the packages in an index, extending the index with a "source".
  # the index returned is also called "fetchedIndex".
  fetchIndex = index:
    l.map
    (pkg: pkg // {source = fetch pkg;})
    index;
in {inherit fetchIndex fetch;}
