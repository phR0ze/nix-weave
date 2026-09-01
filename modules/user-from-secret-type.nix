# Declares the submodule type for users.fromSecret. Modeled on template-type.nix: no isDefined
# auto-detection needed since membership in this namespace is unambiguous by construction.
#---------------------------------------------------------------------------------------------------
{ lib }:
with lib.types; attrsOf (submodule (
  { ... }: {
    options = {
      enable = lib.mkOption {
        type = bool;
        default = true;
        description = "Whether this account should be created.";
      };

      sopsFile = lib.mkOption {
        type = path;
        description = "sops file containing userSecretRef/groupSecretRef.";
      };

      format = lib.mkOption {
        type = enum [ "yaml" "json" "binary" "dotenv" "ini" ];
        default = "yaml";
        description = "Format of sopsFile.";
      };

      userSecretRef = lib.mkOption {
        type = str;
        description = "Key within sopsFile whose decrypted value is the username to create.";
      };

      groupSecretRef = lib.mkOption {
        type = str;
        description = "Key within sopsFile whose decrypted value is the group name to create.";
      };

      isSystemUser = lib.mkOption {
        type = bool;
        default = true;
        description = "Create as a system user/group (useradd/groupadd --system).";
      };

      home = lib.mkOption {
        type = nullOr str;
        default = null;
        description = ''
          Fixed home directory to create (-m). The real username isn't known at eval time, so
          this can't be name-derived like normal users.users.<name>.home. Omit for no home
          directory (-M).
        '';
      };
    };
  }
))
