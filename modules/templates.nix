# `files.templates` -- own standalone namespace for sops-nix-rendered content (mixing ordinary
# plaintext with config.sops.placeholder references for secret values), analogous to how
# users.fromSecret is its own namespace rather than an engine bolted onto files.any/root/user/all
# (see users-from-secret.nix/user-from-secret-type.nix). Kept out of the shared fileType
# submodule used by files.any/root/user/all because that submodule auto-detects which engine an
# entry is using without forcing any option's value, and template content may reference
# config.sops.placeholder -- forcing it prematurely (merely to classify the entry) would recurse,
# since sops-nix only makes sops.placeholder available once it already knows sops.templates is
# non-empty. Being its own namespace sidesteps that: membership in files.templates is unambiguous
# by construction, so there's nothing to classify (see template-type.nix).
#
# Thin passthrough that generates one sops.templates entry (keyed by the files.templates.<name>
# identifier, just like sops.templates."<name>") plus any sops.secrets entries the template needs
# (from files.templates.<name>.secrets), rendered by sops-nix at activation time and placed at
# `path` -- no bespoke activation code needed since sops.templates already supports arbitrary
# path/owner/group/mode.
#---------------------------------------------------------------------------------------------------
{ config, lib, ... }:
let
  types = import ./file-type.nix { inherit lib; pkgs = null; };
  templateType = import ./template-type.nix { inherit lib; inherit (types) ownerRefType; };

  entries = lib.filterAttrs (_: e: e.enable) config.files.templates;

  ownerStr = v: if builtins.isString v then v else "root";

  toTemplate = name: entry: {
    inherit name;
    value =
      {
        path = entry._target;
        owner = ownerStr entry.user;
        group = ownerStr entry.group;
        mode = entry.filemode;
        # Lazily coerced (not `optionalAttrs (... != null)`) so building the sops.templates
        # attrset never forces `content` -- doing so would recurse, since `content` may
        # interpolate config.sops.placeholder, which sops-nix itself only makes available once
        # config.sops.templates is known non-empty (see this file's header comment).
        content = if entry.content == null then "" else entry.content;
      }
      // lib.optionalAttrs (entry.file != null) { file = entry.file; };
  };
in
{
  options.files.templates = lib.mkOption {
    type = templateType;
    default = { };
    description = ''
      Files rendered via sops-nix's template engine: substitutes any config.sops.placeholder
      references in `content`/`file` and installs the result at `path`. The attribute name is
      just an identifier (mirrors sops.templates."<name>"), not the install path. Exactly one of
      `content`/`file` should be set. Any sops.secrets entries the template's placeholders need
      can be registered inline via `secrets` instead of a separate sops.secrets.<key> block.
    '';
    example = ''
      files.templates."cloudflare-env" = {
        path = "/run/caddy/cloudflare.env";
        user = "caddy"; group = "caddy";
        content = '''
          CF_ZONE=$${config.sops.placeholder."caddy/cfZone"}
          CF_API_TOKEN=$${config.sops.placeholder."caddy/cloudflareApiToken"}
        ''';
        secrets = {
          "caddy/cfZone".sopsFile = ./secrets.enc.yaml;
          "caddy/cloudflareApiToken".sopsFile = ./secrets.enc.yaml;
        };
      };
    '';
  };

  config = lib.mkIf (entries != { }) {
    sops.templates = lib.listToAttrs (lib.mapAttrsToList toTemplate entries);
    sops.secrets = lib.mkMerge (lib.mapAttrsToList (_: e: e.secrets) entries);
  };
}
