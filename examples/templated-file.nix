# Templated file -- mixed plaintext + secret fields, via the standalone files.templates
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
  files.templates."cloudflare-env" = {
    path = "/run/caddy/cloudflare.env"; # defaults to /run/secrets/rendered/<name> like sops-nix
    user = "caddy";
    group = "caddy";
    content = ''
      CF_ZONE=${config.files.secret."caddy/cfZone"}
      CF_API_TOKEN=${config.files.secret."caddy/cloudflareApiToken"}
    '';
    secrets = {
      "caddy/cfZone".sopsFile = ./secrets.enc.yaml;
      "caddy/cloudflareApiToken".sopsFile = ./secrets.enc.yaml;
    };
  };
}
