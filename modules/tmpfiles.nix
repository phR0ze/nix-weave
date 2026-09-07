# Ensures the parent directory of every files.secrets/files.templates target exists before
# sops-nix's activation tries to write into it, rather than depending on undocumented
# parent-dir auto-creation behavior for custom `path` overrides on sops.secrets/sops.templates.
#---------------------------------------------------------------------------------------------------
{ config, lib, ... }:
let
  ownerStr = v: if builtins.isString v then v else "root";

  toParentDir = e: {
    dir = builtins.dirOf e.path;
    mode = e.dirmode;
    user = ownerStr e.user;
    group = ownerStr e.group;
  };

  secretEntries = lib.attrValues (lib.filterAttrs (_: e: e.enable) config.files.secrets);

  templateEntries = lib.attrValues (lib.filterAttrs (_: e: e.enable) config.files.templates);

  parentDirs = lib.unique (map toParentDir (secretEntries ++ templateEntries));

  rule = d: "d ${d.dir} ${d.mode} ${d.user} ${d.group} -";
in
{
  config = lib.mkIf (parentDirs != [ ]) {
    systemd.tmpfiles.rules = map rule parentDirs;
  };
}
