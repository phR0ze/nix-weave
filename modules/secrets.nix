# `encrypted` engine: thin passthrough that generates one sops.secrets entry per entry,
# placed directly at the entry's target path. Decryption/placement/permissions are 100%
# delegated to sops-nix -- no bespoke activation code.
#---------------------------------------------------------------------------------------------------
{ config, lib, ... }:
let
  collect = import ./collect.nix { inherit lib; };
  entries = collect { inherit config; engine = "encrypted"; };

  ownerStr = v: if builtins.isString v then v else "root";

  toSecret = entry: {
    name = lib.removePrefix "/" entry.target;
    value = {
      sopsFile = entry.encrypted.sopsFile;
      format = entry.encrypted.format;
      # sops-install-secrets treats "/" in `key` as a path separator into nested maps (not a
      # literal character), so the default must not be the full (slash-containing) target --
      # fall back to just its last path component instead.
      key = if entry.encrypted.key != null then entry.encrypted.key else baseNameOf entry.target;
      path = entry.target;
      owner = ownerStr entry.user;
      group = ownerStr entry.group;
      mode = entry.filemode;
    };
  };
in
{
  config = lib.mkIf (entries != [ ]) {
    sops.secrets = lib.listToAttrs (map toSecret entries);
  };
}
