# Templated file -- mixed plaintext + secret fields, via the standalone secret.templates
# namespace (see modules/template-type.nix). The attribute name is just an identifier (mirrors
# sops.templates."<name>"); `path` is the absolute destination path.
#---------------------------------------------------------------------------------------------------
{ config, ... }:
{
  # 1. Create the sops file
  # sops edit secrets.enc.yaml
  # caddy:
  #   cloudflareApiToken: ENC[AES...]
  #   cfZone: ENC[AES...]

  # 2. Render the template into a file for use, registering the secrets it references inline
  secret.templates."cloudflare-env" = {
    path = "/run/caddy/cloudflare.env"; # defaults to /run/secrets/rendered/<name> like sops-nix
    user = "caddy";
    group = "caddy";
    content = ''
      CF_ZONE=${config.secret.ref."caddy/cfZone"}
      CF_API_TOKEN=${config.secret.ref."caddy/cloudflareApiToken"}
    '';
    secrets = {
      "caddy/cfZone".sopsFile = ./secrets.enc.yaml;
      "caddy/cloudflareApiToken".sopsFile = ./secrets.enc.yaml;
    };
  };
}
