# `template` engine: thin passthrough that generates one sops.templates entry per
# files.templates.<name>, rendered by sops-nix at activation time and placed directly at the
# entry's _target path -- no bespoke activation code needed since sops.templates already
# supports arbitrary path/owner/group/mode.
#
# Reads config.files.templates directly rather than going through collect.nix/files.any/root/
# user/all -- see template-type.nix for why templates are kept in their own namespace.
#---------------------------------------------------------------------------------------------------
{ config, lib, ... }:
let
  entries = lib.filterAttrs (_: e: e.enable) config.files.templates;

  toTemplate = name: entry: {
    inherit name;
    value = {
      content = entry.content;
      path = entry._target;
      owner = entry.user;
      group = entry.group;
      mode = entry.filemode;
    };
  };
in
{
  config = lib.mkIf (entries != { }) {
    sops.templates = lib.mapAttrs' toTemplate entries;
  };
}
