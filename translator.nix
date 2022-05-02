{
  dream2nix,
  system,
  lib,
  ...
}: let
  l = lib // builtins;

  d2n = dream2nix.lib;
  translator = d2n.${system}.translators.translators.rust.all.cargo-lock;

  translate = pkg: let
    tree = d2n.dlib.prepareSourceTree {inherit (pkg) source;};
    # We don't use dream2nix's discoverProjects here since we know
    # there will always be one project (which will be at the root).
    # We also don't need to provide `crates` in subsystem attributes
    # since the source will always only include one crate.
    project = d2n.dlib.construct.discoveredProject {
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
  in
    dreamLock;

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
in
  translateIndex
