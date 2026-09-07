# Shared helper: flatten files.any/root/user/all into one list of enabled entries. Every entry
# is plaintext (copy/weakCopy/link) by construction -- encrypted/encryptedDir live in their own
# standalone files.secrets namespace instead (see secret-type.nix), not in this shared type.
#
# files.any/files.root entries are absolute-path, single-instance as declared. files.user/
# files.all entries are home-relative and get expanded here into one instance per real user
# (every config.users.users entry with isNormalUser = true); files.all additionally gets one
# root-owned /root/<name> instance. This is the one place that knows about the "real users"
# concept -- nixos-files itself has no notion of a single "primary" user.
#---------------------------------------------------------------------------------------------------
{ lib }:
{ config }:
let
  realUsers = lib.filterAttrs (_: u: u.isNormalUser) config.users.users;

  checkRelative = entry:
    if lib.hasPrefix "/" entry.path then
      throw "files.user/files.all name \"${entry.path}\" must be relative to a user's home directory (no leading /) -- use files.any/files.root for absolute paths"
    else entry;

  # One instance of `entry` per real user, path rewritten to that user's home directory.
  expandPerUser = attrs: lib.concatMap
    (entry:
      let e = checkRelative entry; in
      lib.mapAttrsToList
        (uname: u: e // { path = "${u.home}/${e.path}"; user = uname; group = u.group; })
        realUsers)
    (lib.attrValues attrs);

  # One root-owned instance per files.all entry, alongside its per-user expansion.
  allRootVariant = map
    (entry:
      let e = checkRelative entry; in
      e // { user = "root"; group = "root"; path = "/root/${e.path}"; })
    (lib.attrValues config.files.all);

  # files.root is always root:root -- force it here rather than merely defaulting to it in
  # options.nix, same as files.user/files.all force the real per-user (or root) owner.
  rootFiles = map
    (entry: entry // { user = "root"; group = "root"; })
    (lib.attrValues config.files.root);
in
lib.filter (e: e.enable) (lib.concatLists [
  (lib.attrValues config.files.any)
  rootFiles
  (expandPerUser config.files.user)
  (expandPerUser config.files.all)
  allRootVariant
])
