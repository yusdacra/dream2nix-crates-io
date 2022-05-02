{
  dream2nix,
  system,
  lib,
  ...
}: let
  l = lib // builtins;

  d2n = dream2nix.lib.${system};
  dlib = dream2nix.lib.dlib;

  translate = pkg: let
    translator = d2n.translators.translators.rust.all.cargo-lock;

    tree = dlib.prepareSourceTree {inherit (pkg) source;};
    # We don't use dream2nix's discoverProjects here since we know
    # there will always be one project (which will be at the root).
    # We also don't need to provide `crates` in subsystem attributes
    # since the source will always only include one crate.
    project = dlib.construct.discoveredProject {
      subsystem = "rust";
      relPath = "";
      name = pkg.name;
      translators = ["cargo-lock"];
      subsystemInfo = {};
    };
    dreamLock' = translator.translate {
      inherit (pkg) source;
      inherit tree project;
      discoveredProjects = [project];
    };
    # simpleTranslate2 uses .result
    dreamLock = dreamLock'.result or dreamLock';
    # patch this package's dependency to use crates-io source
    # and not a path source.
    dreamLockPatched = l.updateManyAttrsByPath [
      {
        path = ["sources" pkg.name pkg.version];
        update = _: {
          type = "crates-io";
          hash = pkg.sourceHash;
        };
      }
    ]
    dreamLock;
  in
    dreamLockPatched;

  # translates packages in a fetchedIndex, extending them with a "dreamLock",
  # making the index a translatedIndex.
  translateIndex = fetchedIndex: let
    # Filter the fetched index to only get sources with a Cargo.lock
    # others aren't useful to us (we can't translate sources without a Cargo.lock).
    indexWithLocks =
      l.filter
      (pkg: l.pathExists "${pkg.source}/Cargo.lock")
      fetchedIndex;
  in
    l.map
    (pkg: pkg // {dreamLock = translate pkg;})
    indexWithLocks;
in {inherit translate translateIndex;}
