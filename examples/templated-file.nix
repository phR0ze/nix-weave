# Templated file -- mixed plaintext + secret fields, via the `template` field shared by every
# files.any/root/user/all entry (see modules/file-type.nix). The attribute name IS the absolute
# destination path, same as any other files.any entry.
#---------------------------------------------------------------------------------------------------
{ config, ... }:
{
  files.any."/run/caddy/cloudflare.env" = {
    user = "caddy";
    group = "caddy";
    filemode = "0400";
    template.content = ''
      CF_ZONE=example.com
      CF_API_TOKEN=${config.sops.placeholder."caddy/cloudflareApiToken"}
    '';
  };

  sops.secrets."caddy/cloudflareApiToken".sopsFile = ./secrets.enc.yaml;
}
