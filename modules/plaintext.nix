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

  anyFiles = collect { inherit config; engine = "plaintext"; };

  ownerLiteral = entry: field: ownerRef:
    if builtins.isString ownerRef
    then ownerRef
    else "@secret:/run/secrets/_files-owner/${filesLib.ownerSecretId entry._target}/${field}";

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
        (lib.removePrefix "/" entry._target)
        entry._kind
        entry.dirmode
        entry.filemode
        (ownerLiteral entry "user" entry.user)
        (ownerLiteral entry "group" entry.group)
        entry._own
      ])
      anyFiles}
  '';

  installScript = pkgs.writeShellScript "nixos-files-install" (lib.fileContents ./install);

  usesSecretOwner = lib.any (e: !(builtins.isString e.user) || !(builtins.isString e.group)) anyFiles;
in
{
  config = lib.mkIf (anyFiles != [ ]) {
    system.activationScripts.files = lib.stringAfter
      ([ "etc" "users" "groups" ] ++ lib.optional usesSecretOwner "setupSecrets")
      ''${installScript} ${filesPackage} "/nix"'';
  };
}
