# `encryptedDir` engine for files.secrets (see secret-type.nix/secrets.nix) -- author the
# directory's content as one sops-encrypted yaml/json file whose nesting mirrors the directory
# tree (e.g. nginx.certs."server.crt": ENC[...]) -- sops-install-secrets' `key` lookup treats
# "/" as a path separator into nested maps, not a literal character in a flat key, so a
# genuinely flat key like "nginx/certs/server.crt" would NOT resolve. Since sops only ever
# encrypts leaf *values*, never *keys*, the key skeleton can be read at Nix eval time (see
# lib.nix's sopsKeys) without touching ciphertext or plaintext. Each leaf under the declared
# prefix becomes one sops.secrets entry, keyed by its "/"-joined path, placed under target --
# decryption/placement/permissions are 100% delegated to sops-nix.
#---------------------------------------------------------------------------------------------------
{ config, lib, pkgs, ... }:
let
  filesLib = import ./lib.nix { inherit lib pkgs; };

  entries = lib.filter (e: e._engine == "encryptedDir")
    (lib.attrValues (lib.filterAttrs (_: e: e.enable) config.files.secrets));

  relpath = entry: key:
    if entry.encryptedDir.prefix == "" then key
    else lib.removePrefix "${entry.encryptedDir.prefix}/" key;

  toSecrets = entry:
    let
      keys = filesLib.sopsKeys {
        sopsFile = entry.encryptedDir.sopsFile;
        prefix = entry.encryptedDir.prefix;
      };
      # A bare (no leading "/") identifier is used verbatim as each leaf's sops.secrets name --
      # entry.path is then just sops-nix's own "/run/secrets/<id>" default (see
      # _usesDefaultSopsPath in secret-type.nix), so `path` below is omitted per-leaf rather
      # than passed through, letting sops-nix compute the identical "/run/secrets/<id>/<leaf>"
      # default itself.
      base = if entry._usesDefaultSopsPath then entry._id else lib.removePrefix "/" entry.path;
    in
    map
      (key: {
        name = "${base}/${relpath entry key}";
        value = {
          sopsFile = entry.encryptedDir.sopsFile;
          inherit key;
          owner = entry.user;
          group = entry.group;
          mode = entry.filemode;
        } // lib.optionalAttrs (!entry._usesDefaultSopsPath) {
          path = "${entry.path}/${relpath entry key}";
        };
      })
      keys;
in
{
  config = lib.mkIf (entries != [ ]) {
    sops.secrets = lib.listToAttrs (lib.concatMap toSecrets entries);
  };
}
