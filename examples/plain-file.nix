# Plaintext file/directory installation, no sops-nix involved.
#---------------------------------------------------------------------------------------------------
{ ... }:
{
  files.root.".dircolors".copy = "TERM *256color\n";

  files.any."/etc/example/hello".copy = "hello from nix-weave\n";

  # files.user/files.all install for every real (isNormalUser) account -- here, "alice" and "bob".
  users.groups.alice = { };
  users.users.alice = {
    isNormalUser = true;
    group = "alice";
    home = "/home/alice";
  };
  users.groups.bob = { };
  users.users.bob = {
    isNormalUser = true;
    group = "bob";
    home = "/home/bob";
  };

  files.user.".config/example.conf".copy = "example=1\n";

  # Installed at /root/.motd, /home/alice/.motd, and /home/bob/.motd.
  files.all.".motd".copy = "welcome\n";
}
