# `template` engine: thin passthrough that generates one sops.templates entry per
# files.any/root/user/all entry with `template.text`/`template.file` set, rendered by
# sops-nix at activation time and placed directly at the entry's _target path -- no bespoke
# activation code needed since sops.templates already supports arbitrary path/owner/group/mode.
#---------------------------------------------------------------------------------------------------
{ config, lib, ... }:
let
  collect = import ./collect.nix { inherit lib; };
  entries = collect { inherit config; engine = "template"; };

  ownerStr = v: if builtins.isString v then v else "root";

  toTemplate = entry: {
    name = lib.removePrefix "/" entry._target;
    value =
      {
        path = entry._target;
        owner = ownerStr entry.user;
        group = ownerStr entry.group;
        mode = entry.filemode;
        # Lazily coerced (not `optionalAttrs (... != null)`) so building the sops.templates
        # attrset never forces `text` -- doing so would recurse, since `text` may interpolate
        # config.sops.placeholder, which sops-nix itself only makes available once
        # config.sops.templates is known non-empty (see file-type.nix's header comment).
        content = if entry.template.text == null then "" else entry.template.text;
      }
      // lib.optionalAttrs (entry.template.file != null) { file = entry.template.file; };
  };
in
{
  config = lib.mkIf (entries != [ ]) {
    sops.templates = lib.listToAttrs (map toTemplate entries);
  };
}
