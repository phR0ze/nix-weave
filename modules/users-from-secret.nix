# `users.fromSecret` -- creates a system user and group at activation time whose actual names
# are only known after sops-nix decrypts them, so neither ever appears in cleartext in the Nix
# store or git. Unlike files.*, <name> can't double as the real identity (it isn't known at eval
# time) -- it's just an internal identifier, like sops.secrets.<name> today.
#
# NixOS's own declarative users.users/users.groups can't express this: nixpkgs' activation script
# (update-users-groups.pl) rewrites /etc/passwd/group/shadow from attribute names fixed at eval
# time, before any secret is decrypted. So this runs a small useradd/groupadd/usermod script
# instead, after sops-nix's default `setupSecrets` (which itself already runs after the built-in
# `users`/`groups` scripts -- see modules/sops/default.nix in the sops-nix flake input) -- which
# is also why plain (non-secret) `extraGroups` entries can rely on those groups already existing
# by the time this runs.
#
# Also allocates a subuid/subgid range for isNormalUser accounts, mirroring NixOS's
# autoSubUidGidRange default (true for non-system users) so rootless container tooling (podman
# etc.) works the same as it would for a declarative users.users account. update-users-groups.pl
# does this itself for declarative users via /var/lib/nixos/auto-subuid-map; plain `useradd` does
# not (NixOS's own /etc/login.defs carries no SUB_UID_*/SUB_GID_* config for it to key off), so
# it's replicated here directly against /etc/subuid and /etc/subgid, using the same range/step
# nixpkgs uses (100000+, 65536-wide) so allocations here can't collide with declarative ones.
#
# Create-once for the account itself, like weakCopy: re-running activation never touches an
# account that already exists, so it won't reconcile uid/shell/home/password if changed
# out-of-band later -- exactly like real users.users, which also only applies initialPassword
# once. extraGroups is the one exception: membership is (re-)added every activation so it stays
# in sync with the config, but never removed if the list shrinks (see user-from-secret-type.nix).
#---------------------------------------------------------------------------------------------------
{ config, lib, pkgs, ... }:
let
  userFromSecretType = import ./user-from-secret-type.nix { inherit lib; };

  entries = lib.filterAttrs (_: e: e.enable) config.users.fromSecret;

  toSecrets = name: entry:
    [
      {
        name = "_users-from-secret/${name}/user";
        value = { inherit (entry) sopsFile format; key = entry.userSecretRef; };
      }
      {
        name = "_users-from-secret/${name}/group";
        value = { inherit (entry) sopsFile format; key = entry.groupSecretRef; };
      }
    ]
    ++ lib.optional (entry.passwordSecretRef != null) {
      name = "_users-from-secret/${name}/password";
      value = { inherit (entry) sopsFile format; key = entry.passwordSecretRef; };
    };

  # Positional args for the `create_user` shell function below -- kept positional (rather than
  # e.g. env vars) so multiple entries can't clash.
  shellArgsFor = name: entry:
    let
      shell =
        if entry.shell != null then entry.shell
        else if entry.isNormalUser then "${pkgs.bashInteractive}/bin/bash"
        else "${pkgs.shadow}/bin/nologin";
      passwordFile =
        if entry.passwordSecretRef != null
        then "/run/secrets/_users-from-secret/${name}/password"
        else "";
    in
    [
      "create_user"
      "/run/secrets/_users-from-secret/${name}/user"
      "/run/secrets/_users-from-secret/${name}/group"
      (lib.boolToString entry.isNormalUser)
      (if entry.uid != null then toString entry.uid else "")
      shell
      (if entry.home != null then entry.home else "")
      entry.homeMode
      (lib.concatStringsSep "," entry.extraGroups)
      passwordFile
    ];

  createUserScript = pkgs.writeShellScript "nixos-files-create-user" ''
    set -euo pipefail

    # Mirrors update-users-groups.pl's autoSubUidGidRange allocation: same 100000-start,
    # 65536-wide, 29000-slot range, so this can't collide with subuid/subgid entries NixOS's own
    # declarative users already wrote before this script runs.
    allocate_subid_range() {
      local user="$1"
      local min=100000 max=$((100000 + 29000 * 65536 - 65536)) step=65536
      [[ -f /etc/subuid ]] || : > /etc/subuid
      [[ -f /etc/subgid ]] || : > /etc/subgid

      grep -q "^$user:" /etc/subuid 2>/dev/null && return 0

      local start=$min
      while [[ $start -le $max ]]; do
        if ! grep -qE ":$start:" /etc/subuid /etc/subgid 2>/dev/null; then
          echo "$user:$start:65536" >> /etc/subuid
          echo "$user:$start:65536" >> /etc/subgid
          return 0
        fi
        start=$((start + step))
      done
      echo "nixos-files: warning: no free subuid/subgid range for '$user'" >&2
    }

    create_user() {
      local user_file="$1" group_file="$2" is_normal="$3" uid="$4" \
            shell="$5" home="$6" home_mode="$7" extra_groups="$8" password_file="$9"
      local user group

      user="$(cat "$user_file")"
      group="$(cat "$group_file")"

      if ! getent group "$group" >/dev/null; then
        local group_args=()
        [[ "$is_normal" == false ]] && group_args+=(--system)
        groupadd "''${group_args[@]}" "$group"
      fi

      if ! id "$user" >/dev/null 2>&1; then
        local user_args=(-g "$group" -s "$shell")
        [[ "$is_normal" == false ]] && user_args+=(--system)
        [[ -n "$uid" ]] && user_args+=(-u "$uid")

        # The real username is only known now, so a normal user's default home (mirroring
        # users.users.<name>.home) can only be resolved here, not at the Nix level.
        local effective_home="$home"
        if [[ -z "$effective_home" && "$is_normal" == true ]]; then
          effective_home="/home/$user"
        fi

        if [[ -n "$effective_home" ]]; then
          user_args+=(-d "$effective_home" -m)
        else
          user_args+=(-M)
        fi

        useradd "''${user_args[@]}" "$user"

        if [[ -n "$effective_home" ]]; then
          chmod "$home_mode" "$effective_home"
        fi

        if [[ -n "$password_file" ]]; then
          chpasswd <<< "$user:$(cat "$password_file")"
        fi

        [[ "$is_normal" == true ]] && allocate_subid_range "$user"
      fi

      if [[ -n "$extra_groups" ]]; then
        usermod -aG "$extra_groups" "$user"
      fi
    }

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList
      (name: entry: lib.escapeShellArgs (shellArgsFor name entry))
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
