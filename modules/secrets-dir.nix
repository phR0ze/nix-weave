# `encryptedDir` engine: author the directory's content as one sops-encrypted yaml/json file
# whose nesting mirrors the directory tree (e.g. nginx.certs."server.crt": ENC[...]) --
# sops-install-secrets' `key` lookup treats "/" as a path separator into nested maps, not a
# literal character in a flat key, so a genuinely flat key like "nginx/certs/server.crt" would
# NOT resolve. Since sops only ever encrypts leaf *values*, never *keys*, the key skeleton can
# be read at Nix eval time (see lib.nix's sopsKeys) without touching ciphertext or plaintext.
# Each leaf under the declared prefix becomes one sops.secrets entry, keyed by its "/"-joined
# path, placed under target -- decryption/placement/permissions are 100% delegated to sops-nix.
#---------------------------------------------------------------------------------------------------
{ config, lib, pkgs, ... }:
let
  filesLib = import ./lib.nix { inherit lib pkgs; };
  collect = import ./collect.nix { inherit lib; };
  entries = collect { inherit config; engine = "encryptedDir"; };

  ownerStr = v: if builtins.isString v then v else "root";

  relpath = entry: key:
    if entry.encryptedDir.prefix == "" then key
    else lib.removePrefix "${entry.encryptedDir.prefix}/" key;

  toSecrets = entry:
    let
      keys = filesLib.sopsKeys {
        sopsFile = entry.encryptedDir.sopsFile;
        prefix = entry.encryptedDir.prefix;
      };
    in
    map
      (key: {
        name = "${lib.removePrefix "/" entry.target}/${relpath entry key}";
        value = {
          sopsFile = entry.encryptedDir.sopsFile;
          inherit key;
          path = "${entry.target}/${relpath entry key}";
          owner = ownerStr entry.user;
          group = ownerStr entry.group;
          mode = entry.filemode;
        };
      })
      keys;
in
{
  config = lib.mkIf (entries != [ ]) {
    sops.secrets = lib.listToAttrs (lib.concatMap toSecrets entries);
  };
}
