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
    sourceHash = outputs.calcHash "sha256";
    source = outputs.fetched sourceHash;
  in {inherit source sourceHash;};

  # fetches the packages in an index, extending the index with a "source".
  # the index returned is also called "fetchedIndex".
  fetchIndex = index:
    l.map
    (pkg: pkg // (fetch pkg))
    index;
in {inherit fetchIndex fetch;}
