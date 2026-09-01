# Plaintext directory installation (whole tree, readonly symlinks). Illustrative only --
# not wired into `nix flake check` since it needs a real source directory on disk.
#---------------------------------------------------------------------------------------------------
{ ... }:
{
  users.groups.alice = { };
  users.users.alice = {
    isNormalUser = true;
    group = "alice";
    home = "/home/alice";
  };

  files.user.".config/menus".link = ./include/xfce-menus;
}
