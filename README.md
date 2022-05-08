# dream2nix-crates-io

crates.io indexed and translated into dream2nix lockfiles.
The package index & lock files are updated automatically every day (at 06:00 UTC).

See Hydra jobset [here](https://hydra.tomberek.info/jobset/dream2nix-crates-io/dream2nix-crates-io).

### Usage

The generated packages are available under the `packages` output of the flake.

### Generating lock files

1. index with `nix run .#index-top-5k-downloads` (or any of the other index apps)
2. translate with `nix run .#translate`