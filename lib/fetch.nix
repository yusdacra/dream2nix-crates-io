{
  dream2nix,
  lib,
  system,
  ...
}: let
  l = lib // builtins;

  fetchOutputs = dream2nix.lib.${system}.fetchers.fetchers.crates-io.outputs;
  # fetch one package.
  fetch = {
    name,
    version,
    ...
  } @ attrs: let
    outputs = fetchOutputs {
      pname = name;
      inherit version;
    };
    hash = attrs.checksum or (outputs.calcHash "sha256");
    source = outputs.fetched hash;
  in {inherit source hash;};

  # fetches the packages in an index, extending the index with a "source".
  # the index returned is also called "fetchedIndex".
  fetchIndex = index:
    l.mapAttrs
    (
      name: versions:
        l.mapAttrs
        (
          version: checksum:
            fetch {
              inherit
                name
                version
                checksum
                ;
            }
        )
        versions
    )
    index;
in {inherit fetchIndex fetch;}
