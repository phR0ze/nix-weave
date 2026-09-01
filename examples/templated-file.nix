# Templated file -- mixed plaintext + secret fields, arbitrary target path/permissions.
# Templates live in their own files.templates namespace (see modules/template-type.nix for why).
# The attribute name IS the absolute destination path (see modules/template-type.nix).
#---------------------------------------------------------------------------------------------------
{ config, ... }:
{
  files.templates."run/caddy/cloudflare.env" = {
    user = "caddy";
    group = "caddy";
    filemode = "0400";
    content = ''
      CF_ZONE=example.com
      CF_API_TOKEN=${config.sops.placeholder."caddy/cloudflareApiToken"}
    '';
  };

  sops.secrets."caddy/cloudflareApiToken".sopsFile = ./secrets.enc.yaml;
}
