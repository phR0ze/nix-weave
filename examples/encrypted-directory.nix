# Encrypted directory -- one sops file with flat "/"-namespaced keys, fanned out into one
# sops.secrets entry per key at activation time.
#---------------------------------------------------------------------------------------------------
{ ... }:
{
  files.root."nginx-certs" = {
    target = "/etc/nginx/certs";
    encryptedDir = { sopsFile = ./certs.enc.yaml; prefix = "nginx/certs"; };
    filemode = "0400";
  };
}
