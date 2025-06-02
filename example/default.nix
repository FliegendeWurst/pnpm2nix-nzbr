{ mkPnpmPackage, vips, ... }:

mkPnpmPackage {
  src = ./.;

  # needed by sharp
  extraNativeBuildInputs = [ vips ];
}
