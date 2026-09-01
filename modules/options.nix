# Declares the four files.* wrapper namespaces, all sharing the fileType submodule
# (see file-type.nix):
#
#   files.any.<name>   -- arbitrary absolute path (name must start with "/"), owned root:root
#   files.root.<name>  -- under /root/, owned root:root
#   files.user.<name>  -- under every real user's home directory, owned by that user
#   files.all.<name>   -- files.root + files.user combined (root's copy + every real user's copy)
#
# files.user/files.all entries' attribute names are home-relative (e.g. ".dircolors", not
# "/root/.dircolors") and get expanded into one instance per real user (every
# config.users.users entry with isNormalUser = true) in collect.nix -- nixos-files has no
# notion of a single "primary" user. Any `user`/`group` set on a files.user/files.all entry is
# ignored; the real per-user (or root, for files.all's root copy) owner is always used.
#
# The attribute name is always the install path (prefixed per-namespace below); there is no
# settable `target` field, so there's exactly one place path/naming can come from.
#---------------------------------------------------------------------------------------------------
{ lib, pkgs, ... }:
let
  types = import ./file-type.nix { inherit lib pkgs; };
in
{
  options.files = {
    any = lib.mkOption {
      type = types.fileType { user = "root"; group = "root"; prefix = ""; requireAbsolute = true; };
      default = { };
      description = ''
        Files installed at an arbitrary absolute path. The attribute name must start with "/"
        (e.g. "/etc/asound.conf") -- unlike files.root, no prefix is applied automatically.
      '';
      example = ''
        files.any."/etc/asound.conf".copy = "autospawn=no";
      '';
    };

    root = lib.mkOption {
      type = types.fileType { user = "root"; group = "root"; prefix = "/root/"; };
      default = { };
      description = "Files installed under /root/, owned root:root.";
      example = ''
        files.root.".dircolors".copy = ../include/home/.dircolors;
      '';
    };

    user = lib.mkOption {
      type = types.fileType { user = "root"; group = "root"; prefix = ""; };
      default = { };
      description = ''
        Files installed under every real user's home directory (config.users.users entries with
        isNormalUser = true). The attribute name is home-relative, e.g. ".config/menus", not an
        absolute path.
      '';
      example = ''
        files.user.".config/menus".link = ../include/xfce-menus;
      '';
    };

    all = lib.mkOption {
      type = types.fileType { user = "root"; group = "root"; prefix = ""; };
      default = { };
      description = ''
        Files installed both for root (/root/<name>) and for every real user
        (config.users.users entries with isNormalUser = true, at $HOME/<name>). The attribute
        name is home-relative, not an absolute path.
      '';
    };
  };
}
