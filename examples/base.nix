# Minimal stubs to make `nixosSystem { ... }.config.system.build.toplevel` evaluable for
# `nix flake check` -- not a real machine configuration.
#---------------------------------------------------------------------------------------------------
{ lib, ... }:
{
  fileSystems."/" = { device = "/dev/disk/by-label/root"; fsType = "ext4"; };
  boot.loader.grub.device = "nodev";
  system.stateVersion = lib.trivial.release;

  # Satisfies sops-nix's key-source assertion for the examples that declare secrets.
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";

  # No account has a password set, and these are disposable test VMs with nothing worth
  # protecting -- auto-login as root so you can inspect the results without a login prompt.
  services.getty.autologinUser = "root";
}
