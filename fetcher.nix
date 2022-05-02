{
  dream2nix,
  lib,
  system,
  ...
}: let
  l = lib // builtins;

  fetchOutputs = dream2nix.lib.${system}.fetchers.fetchers.crates-io.outputs;
  fetch = pkg: let
    outputs = fetchOutputs {
      pname = pkg.name;
      version = pkg.version;
    };
  in
    outputs.fetched (outputs.calcHash "sha256");

  fetchIndex = index:
    l.map
    (pkg: pkg // {source = fetch pkg;})
    index;
in
  fetchIndex
