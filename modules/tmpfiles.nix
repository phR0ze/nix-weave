# Ensures the parent directory of every encrypted/encryptedDir/template target exists before
# sops-nix's activation tries to write into it, rather than depending on undocumented
# parent-dir auto-creation behavior for custom `path` overrides on sops.secrets/sops.templates.
#---------------------------------------------------------------------------------------------------
{ config, lib, ... }:
let
  collect = import ./collect.nix { inherit lib; };

  ownerStr = v: if builtins.isString v then v else "root";

  entries = lib.filter (e: e._engine != "plaintext") (collect { inherit config; });

  parentDirs = lib.unique (map
    (e: {
      dir = builtins.dirOf e._target;
      mode = e.dirmode;
      user = ownerStr e.user;
      group = ownerStr e.group;
    })
    entries);

  rule = d: "d ${d.dir} ${d.mode} ${d.user} ${d.group} -";
in
{
  config = lib.mkIf (entries != [ ]) {
    systemd.tmpfiles.rules = map rule parentDirs;
  };
}
