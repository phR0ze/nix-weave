# Plaintext engine: builds a filesPackage (like environment.etc) from every copy/weakCopy/
# link entry across files.any/root/user/all, then installs it via a ported activation script.
#
# secretRef-backed user/group values are written into the store's .meta sidecars only as a
# non-sensitive "@secret:<path>" sentinel -- the install script resolves the real value at
# runtime by reading the path sops-nix decrypted it to (see secret-owner.nix).
#---------------------------------------------------------------------------------------------------
{ config, lib, pkgs, ... }:
let
  filesLib = import ./lib.nix { inherit lib; };
  collect = import ./collect.nix { inherit lib; };

  anyFiles = collect { inherit config; };

  ownerLiteral = entry: field: ownerRef:
    if builtins.isString ownerRef
    then ownerRef
    else "@secret:/run/secrets/_files-owner/${filesLib.ownerSecretId entry.path}/${field}";

  filesPackage = pkgs.runCommandLocal "files" { } ''
    set -euo pipefail
    mkdir -p "$out"

    track() {
      local src="$1" dst="$2" kind="$3" dirmode="$4" filemode="$5" user="$6" group="$7" own="$8"

      [[ "''${dst:0:1}" == "/" ]] && echo "paths must not start with a /" && exit 1
      [[ "''${dst: -1}" == "/" ]] && echo "paths must not end with a /" && exit 1

      local meta
      if [[ -d "$src" ]]; then
        meta="$out/$dst.meta.dir"
      else
        meta="$out/$dst.meta.file"
      fi

      local dir
      dir="$(dirname "$dst")"
      [[ "$dir" != "." ]] && mkdir -p "$out/$dir"
      ln -sf "$src" "$out/$dst"

      {
        echo "$kind"
        echo "$src"
        echo "$dirmode"
        echo "$filemode"
        echo "$user"
        echo "$group"
        echo "$own"
      } >> "$meta"
    }

    ${lib.concatMapStringsSep "\n"
      (entry: lib.escapeShellArgs [
        "track"
        "${entry.source}"
        (lib.removePrefix "/" entry.path)
        entry._kind
        entry.dirmode
        entry.filemode
        (ownerLiteral entry "user" entry.user)
        (ownerLiteral entry "group" entry.group)
        entry._own
      ])
      anyFiles}
  '';

  installScript = pkgs.writeShellScript "nix-weave-install" (lib.fileContents ./install);

  usesSecretOwner = lib.any (e: !(builtins.isString e.user) || !(builtins.isString e.group)) anyFiles;

  # Entries aimed at a secret.users account can't be installed until that account exists, since
  # the installer resolves its home out of the passwd database (see `expand_target` in install).
  # usersFromSecret only exists as an activation script when secret.users is non-empty, which is
  # exactly when collect.nix can have emitted one of these -- but the dependency is still made
  # conditional so naming it can never fail the activation script's own closure.
  usesSecretUsers = lib.any (e: lib.hasPrefix "${filesLib.secretUserPrefix}/" e.path) anyFiles;
in
{
  config = lib.mkIf (anyFiles != [ ]) {
    system.activationScripts.files = lib.stringAfter
      ([ "etc" "users" "groups" ]
        ++ lib.optional usesSecretOwner "setupSecrets"
        ++ lib.optional usesSecretUsers "usersFromSecret")
      ''${installScript} ${filesPackage} "/nix"'';
  };
}
