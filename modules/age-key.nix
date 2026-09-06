# Default sops.age.keyFile so consumers don't have to set it explicitly for the common case.
# sops-nix itself has no fallback -- sops.age.keyFile defaults to null and it asserts some key
# source is configured. Activation runs as root, so `~` there is /root; we check both the
# explicit root path and $HOME (for eval-time convenience e.g. VM tests run as the invoking
# user) and prefer whichever actually exists on disk, falling back to the root path so the
# eventual error, if the key is genuinely missing, points at the conventional location.
#---------------------------------------------------------------------------------------------------
{ lib, ... }:
let
  rootKeyFile = "/root/.config/sops/age/keys.txt";
  homeKeyFile = "${builtins.getEnv "HOME"}/.config/sops/age/keys.txt";
in
{
  config.sops.age.keyFile = lib.mkDefault (
    if builtins.pathExists rootKeyFile then
      rootKeyFile
    else if builtins.getEnv "HOME" != "" && builtins.pathExists homeKeyFile then
      homeKeyFile
    else
      rootKeyFile
  );
}
