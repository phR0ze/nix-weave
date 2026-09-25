# Shared helper: flatten files.any/root/user/all into one list of enabled entries. Every entry
# is plaintext (copy/weakCopy/link) by construction -- encrypted/encryptedDir live in their own
# standalone secret.files namespace instead (see secret-type.nix), not in this shared type.
#
# files.any/files.root entries are absolute-path, single-instance as declared. files.user/
# files.all entries are home-relative and get expanded here into one instance per real user
# (every config.users.users entry with isNormalUser = true, plus every config.secret.users
# account that ends up with a home directory); files.all additionally gets one root-owned
# /root/<name> instance. This is the one place that knows about the "real users" concept --
# nix-weave itself has no notion of a single "primary" user.
#
# A secret.users account's real name/group/home aren't known at eval time -- that's the whole
# point of the namespace -- so its instances get a placeholder destination that the install
# script rewrites once sops-nix has decrypted the name (see `secretUserPrefix` in lib.nix).
#---------------------------------------------------------------------------------------------------
{ lib }:
{ config }:
let
  filesLib = import ./lib.nix { inherit lib; };

  realUsers = lib.filterAttrs (_: u: u.isNormalUser) config.users.users;

  # Only accounts that actually get a home directory can host a home-relative file, mirroring
  # users-from-secret.nix's own rule: a normal user defaults to /home/<user>, a system account
  # gets no home unless one was given explicitly.
  secretUsers = lib.filterAttrs
    (_: u: u.enable && (u.isNormalUser || u.home != null))
    config.secret.users;

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

  # One instance of `entry` per secret.users account. The destination keeps a placeholder root
  # segment (rewritten to the real home at activation), and ownership goes through the ordinary
  # secretRef form, so secret-owner.nix generates the very lookup secrets the installer reads
  # back to learn the name -- the same mechanism a hand-written `user = { secretRef = ...; }`
  # already uses, no second path into the installer.
  expandPerSecretUser = attrs: lib.concatMap
    (entry:
      let e = checkRelative entry; in
      lib.mapAttrsToList
        (uname: u: e // {
          path = "${filesLib.secretUserPrefix}/${uname}/${e.path}";
          user = { secretRef = u.userSecretRef; inherit (u) sopsFile; };
          group = { secretRef = u.groupSecretRef; inherit (u) sopsFile; };
        })
        secretUsers)
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
  (expandPerSecretUser config.files.user)
  (expandPerSecretUser config.files.all)
  allRootVariant
])
