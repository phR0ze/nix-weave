# Declares the submodule type for secret.users. Modeled on template-type.nix: no isDefined
# auto-detection needed since membership in this namespace is unambiguous by construction.
#
# Mirrors the shape of NixOS's own users.users/users.groups as closely as the "real name isn't
# known until decrypt time" constraint allows -- isNormalUser, uid, extraGroups, and an initial
# password all behave the same as their users.users.<name> counterparts. Unlike extraGroups
# (plain group names -- membership doesn't reveal the account's own identity), the primary group
# is always secret-sourced via groupSecretRef: a plain `group` option would defeat the point of
# this module for the common case where the account's own group shouldn't appear in cleartext
# either. Declare a plain users.groups.<name> yourself and reference it via extraGroups if you
# want supplementary (not primary) membership in a public group.
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
        description = "sops file containing userSecretRef/groupSecretRef/passwordSecretRef.";
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
        description = "Key within sopsFile whose decrypted value is the primary group name to create.";
      };

      extraGroups = lib.mkOption {
        type = listOf str;
        default = [ ];
        description = ''
          Plain, non-secret supplementary group names (like users.users.<name>.extraGroups) that
          must already exist. Membership is added every activation (usermod -aG) but never
          removed if this list shrinks later -- unlike NixOS's fully declarative reconciliation,
          since the real username is only known at activation time.
        '';
      };

      isNormalUser = lib.mkOption {
        type = bool;
        default = false;
        description = ''
          Same meaning as users.users.<name>.isNormalUser: a real login account (uid from the
          normal range, bash shell and a /home/<user> home directory by default) rather than a
          system account (uid from the system range, nologin shell, no home unless one is given).
        '';
      };

      uid = lib.mkOption {
        type = nullOr int;
        default = null;
        description = "Fixed uid, like users.users.<name>.uid. Omit to let useradd allocate one.";
      };

      shell = lib.mkOption {
        type = nullOr str;
        default = null;
        description = ''
          Path to the login shell. Defaults to bash for isNormalUser accounts and nologin
          otherwise, matching NixOS's own useDefaultShell behavior.
        '';
      };

      home = lib.mkOption {
        type = nullOr str;
        default = null;
        description = ''
          Home directory to create (-m). The real username isn't known at eval time, so this
          can't be name-derived like users.users.<name>.home at the Nix level -- but if left
          unset and isNormalUser is true, it's still resolved to /home/<user> at activation time,
          once the username is known. Set explicitly to override, or leave null with
          isNormalUser = false for no home directory (-M).
        '';
      };

      homeMode = lib.mkOption {
        type = str;
        default = "0700";
        description = "Permissions applied to the home directory once created, like users.users.<name>.homeMode.";
      };

      passwordSecretRef = lib.mkOption {
        type = nullOr str;
        default = null;
        description = ''
          Key within sopsFile whose decrypted value is the initial password, like
          users.users.<name>.initialPassword -- applied only when the account is first created,
          never re-applied or reconciled on later activations. Mutually exclusive with
          passwordHashSecretRef.
        '';
      };

      passwordHashSecretRef = lib.mkOption {
        type = nullOr str;
        default = null;
        description = ''
          Key within sopsFile whose decrypted value is an already-hashed password (e.g. from
          `mkpasswd -m sha-512`), like users.users.<name>.hashedPassword -- applied only when the
          account is first created, never re-applied or reconciled on later activations. Use this
          instead of passwordSecretRef when the plaintext password shouldn't be decrypted to disk
          at all, even transiently. Mutually exclusive with passwordSecretRef.
        '';
      };
    };
  }
))
