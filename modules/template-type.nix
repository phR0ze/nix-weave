# Declares the submodule type for files.templates. Deliberately separate from fileType
# (see file-type.nix) -- membership here is unambiguous by construction (every attrsOf key IS
# a template), so no `isDefined`-based auto-detection of `content` is ever needed, which is
# what makes it safe for `content` to interpolate `config.sops.placeholder."..."`.
#---------------------------------------------------------------------------------------------------
{ lib }:
with lib.types; attrsOf (submodule (
  { name, config, ... }: {
    options = {
      enable = lib.mkOption {
        type = bool;
        default = true;
        description = "Whether this template should be installed.";
      };

      user = lib.mkOption {
        type = str;
        default = "root";
        description = "Owner of the rendered file.";
      };

      group = lib.mkOption {
        type = str;
        default = "root";
        description = "Group of the rendered file.";
      };

      dirmode = lib.mkOption {
        type = str;
        default = "0755";
        description = "Mode of any directories created to hold the rendered file.";
      };

      filemode = lib.mkOption {
        type = str;
        default = "0644";
        description = "Mode of the rendered file.";
      };

      content = lib.mkOption {
        type = lines;
        description = ''
          Template content, mixing ordinary Nix-eval-time text with references to
          config.sops.placeholder for secret values. Rendered by sops-nix at activation time
          and placed at _target.
        '';
      };

      # -- internal, computed --
      _target = lib.mkOption {
        type = str;
        internal = true;
        default = "/${name}";
        description = "Absolute destination path for the rendered template. Not settable directly.";
      };
    };
  }
))
