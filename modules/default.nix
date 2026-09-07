# nixos-files entry point: declares only nixos-files' own options/config (writes into
# config.sops.secrets/config.sops.templates, never re-declares them). sops-nix's own module is
# bundled alongside this one at the flake level -- see flake.nix's `nixosModules.default`, not
# here, since this file has no access to the sops-nix flake input.
#---------------------------------------------------------------------------------------------------
{
  imports = [
    ./age-key.nix
    ./options.nix
    ./plaintext.nix
    ./secret-owner.nix
    ./secrets.nix
    ./secrets-dir.nix
    ./secret.nix
    ./templates.nix
    ./users-from-secret.nix
    ./tmpfiles.nix
  ];
}
