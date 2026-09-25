# Fans a `secret.templates.<name>` entry with `homePath` set out into one copy per account, the
# way collect.nix/plaintext.nix do for plaintext files.user/files.all content.
#
# Plaintext content can be fanned out entirely at eval time because its source is a Nix store
# path -- the installer only has to resolve the *destination*. Rendered secret content can't:
# sops-nix bakes sops.templates.<name>.path into its own setupSecrets script at eval time, so it
# can only ever write to one fixed path, and that path can't be a secret.users account's home
# (whose name isn't known until that same activation decrypts it). So a homePath entry renders
# to its ordinary `path` as a root-only staging file (see templates.nix) and this module installs
# copies from it afterwards, once the passwd database can be read.
#
# Copies are content-stamped rather than force-overwritten. A `copy` content type would clobber
# whatever the owning application wrote back into its own config file on every activation, and a
# `weakCopy` one would never propagate a rotated secret; stamping the rendered content's hash
# per destination gets both -- reinstall when the rendering changed (or the copy went missing),
# leave it alone otherwise.
#---------------------------------------------------------------------------------------------------
{ config, lib, pkgs, ... }:
let
  entries = lib.filterAttrs (_: e: e.enable && e.homePath != null) config.secret.templates;

  realUsers = lib.filterAttrs (_: u: u.isNormalUser) config.users.users;

  # Same rule as collect.nix: only accounts that actually get a home directory can host a
  # home-relative file.
  secretUsers = lib.filterAttrs
    (_: u: u.enable && (u.isNormalUser || u.home != null))
    config.secret.users;

  # The installer needs each secret account's real name to find its home. Generated here rather
  # than reaching for users-from-secret.nix's own `_users-from-secret/<name>/user` secret, so
  # neither module depends on the other's internal secret naming -- mirroring how
  # secret-owner.nix generates its own lookup secrets for secretRef-backed file ownership.
  nameSecrets = lib.mapAttrs'
    (uname: u: {
      name = "_user-templates/${uname}/user";
      value = { inherit (u) sopsFile format; key = u.userSecretRef; };
    })
    secretUsers;

  # Positional args, kept positional (rather than env vars) so entries can't clash.
  installArgs = entry: extra: lib.escapeShellArgs ([
    entry._target
    entry.homePath
    entry.filemode
    entry.dirmode
  ] ++ extra);

  callsFor = entry:
    lib.optional entry.includeRoot ("install_at " + installArgs entry [ "root" "root" "/root" ])
    ++ lib.mapAttrsToList
      (uname: u: "install_at " + installArgs entry [ uname u.group u.home ])
      realUsers
    ++ lib.mapAttrsToList
      (uname: _: "install_for_secret_user " + installArgs entry [ "/run/secrets/_user-templates/${uname}/user" ])
      secretUsers;

  installScript = pkgs.writeShellScript "nix-weave-install-user-templates" ''
    set -euo pipefail

    state_dir="/nix/files.user-templates"
    mkdir -p "$state_dir"

    # Look a username up in the passwd database and print its home directory. Reads /etc/passwd
    # with the shell rather than shelling out to getent, matching modules/install.
    passwd_entry() {
      local _want="$1" _name _gid _home
      while IFS=: read -r _name _ _ _gid _ _home _; do
        if [[ "$_name" == "$_want" ]]; then
          printf '%s\n%s' "$_gid" "$_home"
          return 0
        fi
      done < /etc/passwd
      return 1
    }

    install_at() {
      local _staged="$1" _rel="$2" _filemode="$3" _dirmode="$4" _user="$5" _group="$6" _home="$7"

      # The staging file only exists once sops-nix has rendered it; a template whose secrets
      # failed to decrypt shouldn't take the whole activation down with it.
      if [[ ! -f "$_staged" ]]; then
        echo "nix-weave: warning: $_staged not rendered -- skipping $_home/$_rel" >&2
        return 0
      fi

      local _target="$_home/$_rel"
      local _stamp _want _have=""
      _stamp="$state_dir/$(printf '%s' "$_target" | sha256sum | cut -d' ' -f1)"
      _want="$(sha256sum < "$_staged" | cut -d' ' -f1)"
      [[ -f "$_stamp" ]] && _have="$(cat "$_stamp")"

      # Unchanged rendering and the copy is still there: leave whatever the owning application
      # has since written into it alone.
      if [[ -f "$_target" && "$_have" == "$_want" ]]; then
        return 0
      fi

      install -d -m "$_dirmode" -o "$_user" -g "$_group" "$(dirname "$_target")"
      install -m "$_filemode" -o "$_user" -g "$_group" "$_staged" "$_target"
      printf '%s' "$_want" > "$_stamp"
    }

    # Same, for an account whose name only exists as a decrypted secret: resolve the name, then
    # its gid/home out of the passwd database.
    install_for_secret_user() {
      local _staged="$1" _rel="$2" _filemode="$3" _dirmode="$4" _namefile="$5"

      [[ -f "$_namefile" ]] || return 0
      local _user _fields _gid _home
      _user="$(cat "$_namefile")"
      [[ -n "$_user" ]] || return 0

      if ! _fields="$(passwd_entry "$_user")"; then
        echo "nix-weave: warning: no passwd entry for '$_user' -- skipping $_rel" >&2
        return 0
      fi
      _gid="''${_fields%%$'\n'*}"
      _home="''${_fields#*$'\n'}"
      if [[ -z "$_home" ]]; then
        echo "nix-weave: warning: no home directory for '$_user' -- skipping $_rel" >&2
        return 0
      fi

      install_at "$_staged" "$_rel" "$_filemode" "$_dirmode" "$_user" "$_gid" "$_home"
    }

    ${lib.concatStringsSep "\n    " (lib.concatLists (lib.mapAttrsToList (_: callsFor) entries))}
  '';
in
{
  config = lib.mkIf (entries != { }) {
    assertions = lib.mapAttrsToList
      (name: entry: {
        assertion = entry.path == "/run/secrets/rendered/${name}";
        message = ''
          secret.templates."${name}" sets both `path` and `homePath`. With homePath the rendered
          file is only a staging file the per-user copies come from, so `path` must be left at
          its default -- set homePath alone.
        '';
      })
      entries;

    sops.secrets = nameSecrets;

    # setupSecrets renders the staging files, usersFromSecret creates the accounts whose homes
    # are being written into. The latter only exists as an activation script when secret.users is
    # non-empty, so the dependency is conditional (naming a missing one fails the closure).
    system.activationScripts.userTemplates = lib.stringAfter
      ([ "users" "groups" "setupSecrets" ]
        ++ lib.optional (secretUsers != { }) "usersFromSecret")
      "${installScript}";
  };
}
