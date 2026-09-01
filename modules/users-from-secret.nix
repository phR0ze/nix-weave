# `users.fromSecret` -- creates a system user and group at activation time whose actual names
# are only known after sops-nix decrypts them, so neither ever appears in cleartext in the Nix
# store or git. Unlike files.*, <name> can't double as the real identity (it isn't known at eval
# time) -- it's just an internal identifier, like sops.secrets.<name> today.
#
# NixOS's own declarative users.users/users.groups can't express this: nixpkgs' activation script
# (update-users-groups.pl) rewrites /etc/passwd/group/shadow from attribute names fixed at eval
# time, before any secret is decrypted. So this runs a small useradd/groupadd script instead,
# after sops-nix's default `setupSecrets` (which itself already runs after the built-in `users`/
# `groups` scripts -- see modules/sops/default.nix in the sops-nix flake input).
#
# Create-once, like weakCopy: re-running activation never touches an account that already
# exists, so it won't reconcile group membership or home dir if changed out-of-band later.
#---------------------------------------------------------------------------------------------------
{ config, lib, pkgs, ... }:
let
  userFromSecretType = import ./user-from-secret-type.nix { inherit lib; };

  entries = lib.filterAttrs (_: e: e.enable) config.users.fromSecret;

  toSecrets = name: entry: [
    {
      name = "_users-from-secret/${name}/user";
      value = { inherit (entry) sopsFile format; key = entry.userSecretRef; };
    }
    {
      name = "_users-from-secret/${name}/group";
      value = { inherit (entry) sopsFile format; key = entry.groupSecretRef; };
    }
  ];

  createUserScript = pkgs.writeShellScript "nixos-files-create-user" ''
    set -euo pipefail

    create_user() {
      local user_file="$1" group_file="$2" is_system="$3" home="$4"
      local user group
      user="$(cat "$user_file")"
      group="$(cat "$group_file")"

      if ! getent group "$group" >/dev/null; then
        local group_args=()
        [[ "$is_system" == true ]] && group_args+=(--system)
        groupadd "''${group_args[@]}" "$group"
      fi

      if ! id "$user" >/dev/null 2>&1; then
        local user_args=(-g "$group")
        [[ "$is_system" == true ]] && user_args+=(--system)
        if [[ -n "$home" ]]; then
          user_args+=(-d "$home" -m)
        else
          user_args+=(-M)
        fi
        useradd "''${user_args[@]}" "$user"
      fi
    }

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList
      (name: entry: lib.escapeShellArgs [
        "create_user"
        "/run/secrets/_users-from-secret/${name}/user"
        "/run/secrets/_users-from-secret/${name}/group"
        (lib.boolToString entry.isSystemUser)
        (if entry.home != null then entry.home else "")
      ])
      entries)}
  '';
in
{
  options.users.fromSecret = lib.mkOption {
    type = userFromSecretType;
    default = { };
    description = "System users (and groups) created at activation from decrypted sops secrets.";
    example = ''
      users.fromSecret."svc-account" = {
        sopsFile = ./secrets.enc.yaml;
        userSecretRef = "provisioned/svcUsername";
        groupSecretRef = "provisioned/svcGroupname";
      };
    '';
  };

  config = lib.mkIf (entries != { }) {
    sops.secrets = lib.listToAttrs (lib.concatLists (lib.mapAttrsToList toSecrets entries));

    system.activationScripts.usersFromSecret = lib.stringAfter [ "setupSecrets" ] ''
      ${createUserScript}
    '';
  };
}
