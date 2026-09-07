# Encrypted directory -- one sops file with flat "/"-namespaced keys, fanned out into one
# sops.secrets entry per key at activation time. The attribute name (no leading "/") is a bare
# sops-nix identifier -- each leaf defaults to sops-nix's own "/run/secrets/<name>/<leaf>" path.
#---------------------------------------------------------------------------------------------------
{ ... }:
{
  files.secrets."nginx/certs" = { sopsFile = ./certs.enc.yaml; prefix = "nginx/certs"; };
}
