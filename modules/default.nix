# nixos-files entry point. Deliberately does NOT import sops-nix's own module (only writes into
# config.sops.secrets/config.sops.templates) -- consumers must import
# inputs.sops-nix.nixosModules.sops themselves alongside this module, to avoid duplicate option
# declarations when they also import sops-nix directly for their own secrets.
#---------------------------------------------------------------------------------------------------
{
  imports = [
    ./options.nix
    ./plaintext.nix
    ./secret-owner.nix
    ./secrets.nix
    ./secrets-dir.nix
    ./files-templates.nix
    ./templates.nix
    ./users-from-secret.nix
    ./tmpfiles.nix
  ];
}
