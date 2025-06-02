{ lib
, stdenv
, nodejs
, jq
, moreutils
, pkg-config
, callPackage
, writeText
, runCommand
, ...
}:

with builtins; with lib; with callPackage ./lockfile.nix { };
let
  nodePkg = nodejs;
  pkgConfigPkg = pkg-config;
in
{
  mkPnpmPackage =
    { workspace ? null
    , components ? []
    , src ? if (workspace != null && components != []) then workspace else null
    , packageJSON ? src + "/package.json"
    , componentPackageJSONs ? map (c: {
        name = "${c}/package.json";
        value = src + "/${c}/package.json";
      }) components
    , pnpmLockYaml ? src + "/pnpm-lock.yaml"
    , pnpmWorkspaceYaml ? (if workspace == null then null else workspace + "/pnpm-workspace.yaml")
    , pname ? (fromJSON (readFile packageJSON)).name
    , version ? (fromJSON (readFile packageJSON)).version or null
    , name ? if version != null then "${pname}-${version}" else pname
    , registry ? "https://registry.npmjs.org"
    , script ? "build"
    , scriptFull ? null
    , distDir ? "dist"
    , distDirs ? (if workspace == null then [distDir] else (map (c: "${c}/dist") components))
    , distDirIsOut ? true
    , installNodeModules ? false
    , installPackageFiles ? false
    , installEnv ? { }
    , buildEnv ? { }
    , noDevDependencies ? false
    , extraNodeModuleSources ? [ ]
    , copyNodeModules ? false
    , extraNativeBuildInputs ? [ ]
    , extraBuildInputs ? [ ]
    , nodejs ? nodePkg
    , pnpm ? nodejs.pkgs.pnpm
    , pkg-config ? pkgConfigPkg
    , preBuild ? ""
    , ...
    }@attrs:
    let
      # Flag that can be computed from arguments, indicating a workspace was
      # supplied. Only used in these let bindings.
      isWorkspace = workspace != null && components != [];
      # Utility functions
      forEachConcat = f: xs: concatStringsSep "\n" (map f xs);
      forEachComponent = f: forEachConcat f components;
      # Computed values used below that don't loop
      nativeBuildInputs = [
        nodejs
        pnpm
        pkg-config
      ] ++ extraNativeBuildInputs;
      buildInputs = extraBuildInputs;
      packageFilesWithoutLockfile =
        [
          { name = "package.json"; value = packageJSON; }
        ] ++ componentPackageJSONs ++ computedNodeModuleSources;
      computedNodeModuleSources =
        (if pnpmWorkspaceYaml == null
          then []
          else [
            {name = "pnpm-workspace.yaml"; value = pnpmWorkspaceYaml;}
          ]
        ) ++ extraNodeModuleSources;
      # Computed values that loop over something
      computedDistFiles =
        let
          packageFileNames = ["pnpm-lock.yaml"] ++
            map ({ name, ... }: name) packageFilesWithoutLockfile;
        in
          distDirs ++
            optionals installNodeModules nodeModulesDirs ++
            optionals installPackageFiles packageFileNames;
      nodeModulesDirs =
        if isWorkspace then
          ["node_modules"] ++ (map (c: "${c}/node_modules") components)
        else ["node_modules"];
      filterString = concatStringsSep " " (
        ["--recursive" "--stream"] ++
        map (c: "--filter ./${c}") components
      ) + " ";
      buildScripts = if scriptFull != null then scriptFull else ''
        pnpm run ${optionalString isWorkspace filterString}${script}
      '';
      # Flag derived from value computed above, indicating the single dist
      # should be copied as $out directly, rather than $out/${distDir}
      computedDistDirIsOut =
        length computedDistFiles == 1 && distDirIsOut && !isWorkspace;
    in
    stdenv.mkDerivation (
      recursiveUpdate
        (rec {
          inherit src name nativeBuildInputs buildInputs preBuild;

          strictDeps = true;

          postUnpack = ''
            ${optionalString (pnpmWorkspaceYaml != null) ''
              cp ${pnpmWorkspaceYaml} pnpm-workspace.yaml
            ''}
            ${forEachComponent (component:
              ''mkdir -p "${component}"'')
            }
          '';

          configurePhase = ''
            export HOME=$NIX_BUILD_TOP # Some packages need a writable HOME
            export npm_config_nodedir=${nodejs}

            runHook preConfigure

            store=$(pnpm store path)
            mkdir -p $(dirname $store)

            cp -f ${passthru.patchedLockfileYaml} pnpm-lock.yaml

            pnpm store add $(cat ${passthru.processResultAllDeps})

            ${concatStringsSep "\n" (
              mapAttrsToList
                (n: v: ''export ${n}="${v}"'')
                installEnv
            )}

            pnpm install ${optionalString noDevDependencies "--prod"} \
              --ignore-scripts \
              --force \
              --frozen-lockfile

            runHook postConfigure
          '';

          buildPhase = ''
            ${concatStringsSep "\n" (
              mapAttrsToList
                (n: v: ''export ${n}="${v}"'')
                buildEnv
            )}

            runHook preBuild

            ${buildScripts}

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            ${if computedDistDirIsOut then ''
                ${if distDir == "." then "cp -r" else "mv"} ${distDir} $out
              ''
              else ''
                mkdir -p $out
                ${forEachConcat (dDir: ''
                    cp -r --parents ${dDir} $out
                  '') computedDistFiles
                }
              ''
            }

            runHook postInstall
          '';

          passthru =
            let
              processResult = processLockfile { inherit registry noDevDependencies; lockfile = pnpmLockYaml; };
            in
            {
              inherit attrs processResult;

              patchedLockfile = processResult.patchedLockfile;
              patchedLockfileYaml = writeText "pnpm-lock.yaml" (toJSON passthru.patchedLockfile);

              processResultAllDeps = runCommand "${name}-dependency-list" {} ''
                  echo ${concatStringsSep " " (unique processResult.dependencyTarballs)} > $out
                '';
            };
        })
        (attrs // { extraNodeModuleSources = null; installEnv = null; buildEnv = null;})
    );
}
