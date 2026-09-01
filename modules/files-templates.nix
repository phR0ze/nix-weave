# files.templates -- rendered by sops-nix at activation time, mixing plaintext and secret
# (config.sops.placeholder) content. Kept as its own namespace, separate from
# files.any/root/user/all -- see template-type.nix and templates.nix for why.
#---------------------------------------------------------------------------------------------------
{ lib, ... }:
let
  templateType = import ./template-type.nix { inherit lib; };
in
{
  options.files.templates = lib.mkOption {
    type = templateType;
    default = { };
    description = "Templated files rendered from mixed plaintext + secret content.";
    example = ''
      files.templates."caddy-env" = {
        target = "/run/caddy/cloudflare.env";
        user = "caddy"; group = "caddy"; filemode = "0400";
        content = "CF_API_TOKEN=''${config.sops.placeholder."caddy/cloudflareApiToken"}";
      };
    '';
  };
}
