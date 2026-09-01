# Minimal stubs to make `nixosSystem { ... }.config.system.build.toplevel` evaluable for
# `nix flake check` -- not a real machine configuration.
#---------------------------------------------------------------------------------------------------
{ lib, ... }:
{
  fileSystems."/" = { device = "/dev/disk/by-label/root"; fsType = "ext4"; };
  boot.loader.grub.device = "nodev";
  system.stateVersion = lib.trivial.release;

  # Satisfies sops-nix's key-source assertion for the examples that declare secrets. The key
  # itself is the same disposable test-only age key used throughout examples/ and tests/ (see
  # tests/keys/README.md) -- baked into the VM here purely so `nixos-rebuild build-vm` boots
  # straight into a working example with no manual key-copying step. Never do this with a real
  # key: it would land the private key in the world-readable Nix store.
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  systemd.tmpfiles.rules = [
    "d /var/lib/sops-nix 0700 root root -"
    "C /var/lib/sops-nix/key.txt 0400 root root - ${../tests/keys/test-age-key.txt}"
  ];

  # No account has a password set, and these are disposable test VMs with nothing worth
  # protecting -- auto-login as root so you can inspect the results without a login prompt.
  services.getty.autologinUser = "root";
}
