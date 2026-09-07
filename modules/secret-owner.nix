# Generates internal sops.secrets entries for every secretRef-backed user/group value on a
# plaintext (copy/weakCopy/link) entry, so the ported install script can resolve the real
# owner name at activation time via the "@secret:<path>" sentinel written into the store's
# .meta sidecars (see plaintext.nix).
#
# Left at sops-nix's default /run/secrets/... path -- this is metadata to be *read* by the
# installer, not content to be placed at a final destination path.
#---------------------------------------------------------------------------------------------------
{ config, lib, ... }:
let
  filesLib = import ./lib.nix { inherit lib; };
  collect = import ./collect.nix { inherit lib; };

  entries = collect { inherit config; };

  refEntry = entry: field:
    let ref = entry.${field}; in
    lib.optional (!(builtins.isString ref)) {
      name = "_files-owner/${filesLib.ownerSecretId entry.path}/${field}";
      value = {
        sopsFile = ref.sopsFile;
        key = ref.secretRef;
      };
    };

  secretOwnerEntries = lib.concatMap
    (entry: refEntry entry "user" ++ refEntry entry "group")
    entries;
in
{
  config = lib.mkIf (secretOwnerEntries != [ ]) {
    sops.secrets = lib.listToAttrs secretOwnerEntries;
  };
}
