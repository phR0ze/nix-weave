# Declares the submodule type for files.templates. Modeled on user-from-secret-type.nix: no
# isDefined auto-detection needed since membership in this namespace is unambiguous by
# construction -- unlike file-type.nix's copy/weakCopy/link/encrypted/encryptedDir, which all
# share one submodule and must be disambiguated from one another.
#
# The attribute name is just an identifier (mirrors sops.templates."<name>" -- it is NOT the
# install path). `path` is the install path, defaulting to sops-nix's own
# /run/secrets/rendered/<name> convention, exactly like sops.templates.<name>.path.
#
# Rendered by sops-nix's own template engine (see templates.nix): substitutes any
# config.sops.placeholder references in content/file and installs the result at `path`. Exactly
# one of content/file should be set -- file takes precedence over content if both are given,
# matching sops-nix's own sops.templates.<name>.file/.content precedence.
#---------------------------------------------------------------------------------------------------
{ lib, ownerRefType }:
with lib.types; attrsOf (submodule (
  { name, config, ... }: {
    options = {
      enable = lib.mkOption {
        type = bool;
        default = true;
        description = "Whether this entry should be installed.";
      };

      path = lib.mkOption {
        type = str;
        default = "/run/secrets/rendered/${name}";
        description = ''
          Absolute path where the rendered file is installed. Mirrors sops-nix's own
          sops.templates.<name>.path -- defaults to /run/secrets/rendered/<name>, but should
          normally be overridden (e.g. "/run/caddy/cloudflare.env").
        '';
      };

      user = lib.mkOption {
        type = ownerRefType;
        default = "root";
        description = "Owner of the rendered file, or a secretRef to resolve it from a sops secret at activation time.";
      };

      group = lib.mkOption {
        type = ownerRefType;
        default = "root";
        description = "Group of the rendered file, or a secretRef to resolve it from a sops secret at activation time.";
      };

      dirmode = lib.mkOption {
        type = str;
        default = "0755";
        description = "Mode of any directories created to hold this entry.";
      };

      filemode = lib.mkOption {
        type = str;
        default = "0400";
        description = "Mode of the installed file.";
      };

      content = lib.mkOption {
        type = nullOr lines;
        default = null;
        description = ''
          Template content, mixing ordinary Nix-eval-time text with references to
          config.sops.placeholder for secret values. Rendered by sops-nix at activation time.
          Ignored if `file` is also set.
        '';
      };

      file = lib.mkOption {
        type = nullOr path;
        default = null;
        description = ''
          Path to template content, as an alternative to inline `content`. Takes precedence over
          `content` if both are set (matches sops-nix's own sops.templates.<name>.file/.content
          precedence).
        '';
      };

      secrets = lib.mkOption {
        type = attrsOf attrs;
        default = { };
        description = ''
          sops.secrets.<key> entries this template's content/file needs registered -- each
          attribute here is set verbatim as sops.secrets."<key>" = <value>, keyed the same way
          you'd reference it via config.sops.placeholder."<key>" in `content`.
        '';
      };

      # -- internal, computed --
      _target = lib.mkOption {
        type = str;
        internal = true;
        description = "Absolute destination path: same as `path`. Not settable directly.";
      };
    };

    config._target =
      if lib.hasPrefix "/" config.path then config.path
      else throw "files.templates.\"${name}\".path must be an absolute path starting with \"/\" (e.g. \"/run/caddy/cloudflare.env\")";
  }
))
