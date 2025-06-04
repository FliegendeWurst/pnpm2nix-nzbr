# pnpm2nix

> [!Important]
> 
> This fork supports pnpm 10 and pnpm workspaces.

Provides a `mkPnpmPackage` function that can be used to build a pnpm package with nix.

The function can be accessed either by importing this repo as a flake input or though `pkgs.callPackage /path/to/this/repo/derivation.nix {}`.

In addition to all arguments accepted by `stdenv.mkDerivation`, the `mkPnpmPackage` function accepts the following arguments:

| argument                 | description                                                                 | default                      |
| ------------------------ | --------------------------------------------------------------------------- | ---------------------------- |
| `src`                    | The path to the package sources (required)                                  |                              |
| `packageJSON`            | Override the path to `package.json` (strongly recommended)                  | `${src}/package.json`        |
| `pnpmLockYaml`           | Override the path to `pnpm-lock.yaml` (strongly recommended)                | `${src}/pnpm-lock.yaml`      |
| `workspace`              | The path to the workspace (optional)                                        | `null`                       |
| `components`             | List of workspace members (required if `workspace != null`)                 | `[]`                         |
| `pnpmWorkspaceYaml`      | Override the path to `pnpm-workspace.yaml` (strongly recommended)           | `${workspace}/pnpm-workspace.yaml` |
| `pname`                  | Override the package name                                                   | read from `package.json`     |
| `version`                | Override the package version                                                | read from `package.json`     |
| `name`                   | Override the combined package name                                          | `${pname}-${version}`        |
| `nodejs`                 | Override the nodejs package that is used (recommended)                      | `pkgs.nodejs`                |
| `pnpm`                   | Override the pnpm package that is used (strongly recommended)               | `pkgs.nodejs.pkgs.pnpm`      |
| `registry`               | The registry where the dependencies are downloaded from (sometimes ignored) | `https://registry.npmjs.org` |
| `script`                 | The npm script that is executed                                             | `build`                      |
| `scriptFull`             | The full pnpm invocation (overrides `script`)                               | `null`                       |
| `distDir`                | The directory that should be copied to the output                           | `dist`                       |
| `distDirs`               |                                                                             | `[distDir]` (if `workspace == null`) |
| `distDirIsOut`           |                                                                             | `true`                       |
| `installNodeModules`     |                                                                             | `false`                      |
| `installPackageFiles`    |                                                                             | `false`                      |
| `installEnv`             | Environment variables that should be present during `pnpm install`          | `{}`                         |
| `buildEnv`               | Environment variables that should be present during build phase             | `{}`                         |
| `noDevDependencies`      | Only download and install `dependencies`, not `devDependencies`             | `false`                      |
| `extraNodeModuleSources` | Additional files that should be available during `pnpm install`             | `[]`                         |
| `copyNodeModules`        | Copy the `node_modules` into the build directory instead of linking it      | `false`                      |
| `extraNativeBuildInputs` | Additional entries for `nativeBuildInputs`                                  | `[]`                         |
| `extraBuildInputs`       | Additional entries for `buildInputs`                                        | `[]`                         |
| `preBuild`               | Commands to execute before the main build phase                             | `""`                         |
| `pkg-config`             | Override the pkg-config package that is used                                | `pkgs.pkg-config`            |

## Internals

The supplied `pnpmLockYaml` is processed using a lot of (slow) IFD logic.
To cache those results more efficiently, pass it explicitly as `pnpmLockYaml = ./pnpm-lock.yaml`.
