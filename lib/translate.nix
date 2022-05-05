{
  dream2nix,
  system,
  lib,
  ...
}: let
  l = lib // builtins;

  d2n = dream2nix.lib.${system};
  dlib = dream2nix.lib.dlib;

  translate = {
    name,
    version,
    source,
    hash,
  }: let
    translator = d2n.translators.translators.rust.all.cargo-lock;

    # We don't use dream2nix's discoverProjects here since we know
    # there will always be one project (which will be at the root).
    # We also don't need to provide `crates` in subsystem attributes
    # since the source will always only include one crate.
    project = dlib.construct.discoveredProject {
      inherit name;
      subsystem = "rust";
      relPath = "";
      translators = ["cargo-lock"];
      subsystemInfo = {};
    };
    dreamLock' = translator.translate {
      inherit project source;
      discoveredProjects = [project];
    };
    # simpleTranslate2 uses .result
    dreamLock = dreamLock'.result or dreamLock';
    # patch this package's dependency to use crates-io source
    # and not a path source.
    dreamLockPatched =
      l.updateManyAttrsByPath [
        {
          path = ["sources" name version];
          update = _: {
            type = "crates-io";
            inherit hash;
          };
        }
      ]
      dreamLock;
    # compress the dream lock
    dreamLockCompressed = d2n.utils.dreamLock.compressDreamLock dreamLockPatched;
  in
    dreamLockCompressed;

  # translates packages in a fetchedIndex, extending them with a "dreamLock",
  # making the index a translatedIndex.
  translateIndex = fetchedIndex:
    l.mapAttrs
    (
      name: versions:
        l.mapAttrs
        (
          version: srcInfo:
            translate (srcInfo // {inherit name version;})
        )
        versions
    )
    fetchedIndex;
in {inherit translate translateIndex;}
