# Single encrypted file -- decrypted only at activation, never in the store or git. The
# attribute name (no leading "/") doubles as the sops key lookup and defaults the install path
# to sops-nix's own "/run/secrets/<name>" convention.
#---------------------------------------------------------------------------------------------------
{ ... }:
{
  secret.files."newt/clientSecret".sopsFile = ./secrets.enc.yaml;
}
