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
    # A bare (no leading "/") files.any identifier is used verbatim as the sops.secrets name --
    # entry.path is then just sops-nix's own default, not a real override (see
    # _usesDefaultSopsPath in file-type.nix), so `path` below is omitted rather than passed
    # through, letting sops-nix compute the identical default itself.
    name = if entry._usesDefaultSopsPath then entry._id else lib.removePrefix "/" entry.path;
    value = {
      sopsFile = entry.encrypted.sopsFile;
      format = entry.encrypted.format;
      # sops-install-secrets treats "/" in `key` as a path separator into nested maps (not a
      # literal character), so an explicit target's default must not be the full
      # (slash-containing) path -- fall back to just its last path component instead. A bare
      # identifier has no such ambiguity: it's used as-is, exactly like sops-nix's own default.
      key =
        if entry.encrypted.key != null then entry.encrypted.key
        else if entry._usesDefaultSopsPath then entry._id
        else baseNameOf entry.path;
      owner = ownerStr entry.user;
      group = ownerStr entry.group;
      mode = entry.filemode;
    } // lib.optionalAttrs (!entry._usesDefaultSopsPath) { path = entry.path; };
  };
in
{
  config = lib.mkIf (entries != [ ]) {
    sops.secrets = lib.listToAttrs (map toSecret entries);
  };
}
