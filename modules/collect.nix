# Shared helper: flatten files.any/root/user/all into one list of enabled entries.
#
# files.any/files.root entries are absolute-path, single-instance as declared. files.user/
# files.all entries are home-relative and get expanded here into one instance per real user
# (every config.users.users entry with isNormalUser = true); files.all additionally gets one
# root-owned /root/<name> instance. This is the one place that knows about the "real users"
# concept -- nixos-files itself has no notion of a single "primary" user.
#---------------------------------------------------------------------------------------------------
{ lib }:
{ config, engine ? null }:
let
  matches = e: e.enable && (engine == null || e._engine == engine);

  realUsers = lib.filterAttrs (_: u: u.isNormalUser) config.users.users;

  checkRelative = entry:
    if lib.hasPrefix "/" entry._target then
      throw "files.user/files.all name \"${entry._target}\" must be relative to a user's home directory (no leading /) -- use files.any/files.root for absolute paths"
    else entry;

  # One instance of `entry` per real user, _target rewritten to that user's home directory.
  expandPerUser = attrs: lib.concatMap
    (entry:
      let e = checkRelative entry; in
      lib.mapAttrsToList
        (uname: u: e // { _target = "${u.home}/${e._target}"; user = uname; group = u.group; })
        realUsers)
    (lib.attrValues attrs);

  # One root-owned instance per files.all entry, alongside its per-user expansion.
  allRootVariant = map
    (entry:
      let e = checkRelative entry; in
      e // { user = "root"; group = "root"; _target = "/root/${e._target}"; })
    (lib.attrValues config.files.all);
in
lib.filter matches (lib.concatLists [
  (lib.attrValues config.files.any)
  (lib.attrValues config.files.root)
  (expandPerUser config.files.user)
  (expandPerUser config.files.all)
  allRootVariant
])
