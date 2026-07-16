{ lib
, runCommand
, remarshal
, fetchurl
, ...
}:

with lib;
rec {

  parseLockfile = lockfile: builtins.fromJSON (readFile (runCommand "toJSON" { } "${remarshal}/bin/yaml2json ${lockfile} $out"));

  # targetOs/targetCpu: pnpm platform identifiers (e.g., "linux", "darwin", "win32" / "x64", "arm64", "ia32")
  # Set to null to disable filtering for that dimension
  processLockfile = { registry, lockfile, noDevDependencies, targetOs ? null, targetCpu ? null }:
    let
      splitVersion = name: splitString "@" (head (splitString "(" name));
      getVersion = name: last (splitVersion name);
      withoutVersion = name: concatStringsSep "@" (init (splitVersion name));

      # Check if a package is compatible with the target platform
      # A package is compatible if:
      # 1. It has no os restriction, OR its os list includes targetOs (or targetOs is null)
      # 2. It has no cpu restriction, OR its cpu list includes targetCpu (or targetCpu is null)
      isPlatformCompatible = v:
        let
          osOk = targetOs == null || !(v ? os) || elem targetOs v.os;
          cpuOk = targetCpu == null || !(v ? cpu) || elem targetCpu v.cpu;
        in
        osOk && cpuOk;

      switch = n: v: options:
        if ((length options) == 0)
        then throw "No matching case found, for n=${n} v=${builtins.toJSON v}!"
        else
          if ((head options).case or true)
          then (head options).result
          else switch n v (tail options);
      mkTarball = pkg: contents:
        runCommand "${last (init (splitString "/" (head (splitString "(" pkg))))}.tgz" { } ''
          tar -czf $out -C ${contents} .
        '';
      findTarball = n: v:
        switch n v [
          {
            case = (v.resolution.type or "") == "git";
            result =
              mkTarball n (
                fetchGit {
                  url = v.resolution.repo;
                  rev = v.resolution.commit;
                  shallow = true;
                }
              );
          }
          {
            case = hasPrefix "https://codeload.github.com" (v.resolution.tarball or "");
            result =
              let
                m = strings.match "https://codeload.github.com/([^/]+)/([^/]+)/tar\\.gz/([a-f0-9]+)" v.resolution.tarball;
              in
              mkTarball n (
                fetchGit {
                  url = "https://github.com/${elemAt m 0}/${elemAt m 1}";
                  rev = (elemAt m 2);
                  shallow = true;
                }
              );
          }
          {
            case = hasAttrByPath [ "resolution" "tarball" ] v && hasAttrByPath [ "resolution" "integrity" ] v;
            result = fetchurl {
              url = v.resolution.tarball;
              ${head (splitString "-" v.resolution.integrity)} = v.resolution.integrity;
            };
          }
          {
            case = (v ? id);
            result =
              let
                split = splitString "/" v.id;
              in
              mkTarball n (
                fetchGit {
                  url = "https://${concatStringsSep "/" (init split)}.git";
                  rev = (last split);
                  shallow = true;
                }
              );
          }
          {
            # Handles standard registry packages. In lockfile v9 (pnpm 10)
            # packages in the `packages` section only carry `resolution.integrity`
            # with no explicit tarball URL, so the URL is reconstructed from the
            # package name and version. Earlier lockfile versions with explicit
            # tarball URLs are caught by the case above.
            case = true;
            result =
              let
                name = withoutVersion n;
                baseName = last (splitString "/" (withoutVersion n));
                version = getVersion n;
              in
              fetchurl {
                url = "${registry}/${name}/-/${baseName}-${version}.tgz";
                ${head (splitString "-" v.resolution.integrity)} = v.resolution.integrity;
              };
          }
        ];
    in
    {
      dependencyTarballs =
        unique (
          mapAttrsToList
            findTarball
            (filterAttrs
              (n: v:
                (!noDevDependencies || !(v.dev or false)) &&
                isPlatformCompatible v
              )
              (parseLockfile lockfile).packages
            )
        );

      patchedLockfile =
        let
          orig = parseLockfile lockfile;
          # Get the set of package names that are incompatible
          incompatiblePackageNames = attrNames (filterAttrs (n: v: !isPlatformCompatible v) orig.packages);
          # Filter packages
          filteredPackages = filterAttrs (n: v: isPlatformCompatible v) orig.packages;
          # Helper to filter dependency attrs, removing references to incompatible packages
          filterDeps = deps:
            if deps == null then null
            else filterAttrs (name: version:
              let
                # Construct the package key as it appears in packages (name@version)
                pkgKey = "${name}@${version}";
              in
              !elem pkgKey incompatiblePackageNames
            ) deps;
          # Filter snapshots to remove references to incompatible packages
          filteredSnapshots =
            if orig ? snapshots then
              mapAttrs (n: v:
                v // (
                  optionalAttrs (v ? dependencies) { dependencies = filterDeps v.dependencies; }
                ) // (
                  optionalAttrs (v ? optionalDependencies) { optionalDependencies = filterDeps v.optionalDependencies; }
                )
              ) orig.snapshots
            else {};
        in
        orig // {
          packages = mapAttrs
            (n: v:
              v // (
                if noDevDependencies && (v.dev or false)
                then { resolution = { }; }
                else {
                  # Preserve integrity alongside the injected tarball path.
                  # pnpm v9 uses a content-addressable store indexed by integrity
                  # hash, so keeping it lets `pnpm store add` pre-population work
                  # without internet access. Non-registry packages (git, etc.) have
                  # no integrity field and get only the tarball path.
                  resolution =
                    (if (v.resolution or { }) ? integrity
                    then { inherit (v.resolution) integrity; }
                    else { })
                    // { tarball = "file:${findTarball n v}"; };
                }
              )
            )
            filteredPackages;
          snapshots = filteredSnapshots;
        };
    };

}
