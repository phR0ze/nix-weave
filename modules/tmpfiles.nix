# Ensures the parent directory of every encrypted/encryptedDir/template target exists before
# sops-nix's activation tries to write into it, rather than depending on undocumented
# parent-dir auto-creation behavior for custom `path` overrides on sops.secrets/sops.templates.
#---------------------------------------------------------------------------------------------------
{ config, lib, ... }:
let
  collect = import ./collect.nix { inherit lib; };

  ownerStr = v: if builtins.isString v then v else "root";

  toParentDir = e: {
    dir = builtins.dirOf e._target;
    mode = e.dirmode;
    user = ownerStr e.user;
    group = ownerStr e.group;
  };

  fileEntries = lib.filter (e: e._engine != "plaintext") (collect { inherit config; });

  templateEntries = lib.attrValues (lib.filterAttrs (_: e: e.enable) config.files.templates);

  parentDirs = lib.unique (map toParentDir (fileEntries ++ templateEntries));

  rule = d: "d ${d.dir} ${d.mode} ${d.user} ${d.group} -";
in
{
  config = lib.mkIf (parentDirs != [ ]) {
    systemd.tmpfiles.rules = map rule parentDirs;
  };
}
