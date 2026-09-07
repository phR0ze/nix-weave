# Declares the shared fileType submodule used by files.any/files.root/files.user/files.all for
# plaintext content only (copy/weakCopy/link) -- installed via the ported activation script.
#
# Encrypted content (sops-nix's own sops.secrets) lives in its own standalone
# `files.secrets.<name>` namespace instead (see secret-type.nix/secrets.nix/secrets-dir.nix),
# and rendered (sops-nix template) content in `files.templates.<name>` (see
# template-type.nix/templates.nix) -- both split out rather than being additional engines here,
# so membership in each is unambiguous by construction and files.any/root/user/all stay simple:
# every entry is plaintext, and (for files.any) the attribute name is always a real, absolute
# install path.
#
# `user`/`group` normally take a plain string, but may instead take `{ secretRef; sopsFile; }`
# to resolve the actual owner name from a sops secret at activation time.
#---------------------------------------------------------------------------------------------------
{ lib, pkgs }:
let
  ownerRefType = with lib.types; either str (submodule {
    options = {
      secretRef = lib.mkOption {
        type = str;
        description = "Flat sops key whose decrypted value is the literal user/group name.";
      };
      sopsFile = lib.mkOption {
        type = path;
        description = "sops file containing secretRef.";
      };
    };
  });

  fileType = { user, group, prefix, requireAbsolute ? false }: with lib.types; attrsOf (submodule (
    { name, config, options, ... }: {
      options = {
        enable = lib.mkOption {
          type = bool;
          default = true;
          description = "Whether this entry should be installed.";
        };

        user = lib.mkOption {
          type = ownerRefType;
          default = user;
          description = "Owner of the file, or a secretRef to resolve it from a sops secret at activation time.";
        };

        group = lib.mkOption {
          type = ownerRefType;
          default = group;
          description = "Group of the file, or a secretRef to resolve it from a sops secret at activation time.";
        };

        dirmode = lib.mkOption {
          type = str;
          default = "0755";
          description = "Mode of any directories created to hold this entry.";
        };

        filemode = lib.mkOption {
          type = str;
          default = "0644";
          description = "Mode of the installed file.";
        };

        # NOTE: copy/weakCopy/link deliberately have NO `default`. `_kind`/`source` below are
        # computed from `options.*.isDefined` rather than `config.* != null` -- and `isDefined`
        # is true whenever a `default` is declared, even `default = null`, regardless of
        # whether the caller actually set it. Omitting the default keeps `isDefined` meaningful.

        copy = lib.mkOption {
          type = nullOr (either lines path);
          description = ''
            Content to force-overwrite copy on every switch (kind=copy, owned): a string is
            rendered to a Nix store path first (not necessarily ASCII/text), a path is used
            directly.
          '';
        };

        weakCopy = lib.mkOption {
          type = nullOr (either lines path);
          description = ''
            Content to copy once -- skipped if the target already exists (kind=copy, unowned): a
            string is rendered to a Nix store path first, a path is used directly.
          '';
        };

        link = lib.mkOption {
          type = nullOr (either lines path);
          description = ''
            Content installed as a readonly symlink (kind=link): a string is rendered to a Nix
            store path first (not necessarily ASCII/text, but always a single file -- a directory
            tree requires a path), a path (file or directory) is used directly.
          '';
        };

        # -- read-only, computed --
        path = lib.mkOption {
          type = str;
          description = ''
            Absolute destination path: prefix + attribute name. Not settable directly -- mirrors
            config.sops.secrets."<name>".path, so this can be referenced as an input elsewhere
            (e.g. a systemd unit's EnvironmentFile) once the entry is installed.
          '';
        };

        # -- internal, computed --
        source = lib.mkOption {
          type = nullOr path;
          internal = true;
          default = null;
        };

        _kind = lib.mkOption {
          type = enum [ "copy" "link" ];
          internal = true;
          description = "Computed kind for the plaintext engine.";
        };

        _own = lib.mkOption {
          type = enum [ "owned" "unowned" ];
          internal = true;
          description = "Computed ownership for the plaintext engine's stale-file GC.";
        };
      };

      config =
        let
          # Exactly one install mechanism may be set per entry -- _kind/source below each pick a
          # different one via differing precedence if more than one is set, so silently mixing
          # e.g. copy+link would install with mismatched kind/source rather than erroring.
          setMechanisms = lib.filter (m: m.isDefined) [
            { name = "copy"; isDefined = options.copy.isDefined; }
            { name = "weakCopy"; isDefined = options.weakCopy.isDefined; }
            { name = "link"; isDefined = options.link.isDefined; }
          ];
          tooMany = lib.length setMechanisms > 1;
        in
        {
          path =
            if requireAbsolute && !(lib.hasPrefix "/" name) then
              throw "files.any.\"${name}\" must be an absolute path starting with \"/\" (e.g. files.any.\"/etc/asound.conf\")"
            else "${prefix}${name}";

          _kind =
            if tooMany then
              throw "files.*.\"${name}\" sets more than one install mechanism (${lib.concatMapStringsSep ", " (m: m.name) setMechanisms}) -- set exactly one of copy/weakCopy/link"
            else if options.link.isDefined then "link"
            else "copy";

          _own = if options.weakCopy.isDefined then "unowned" else "owned";

          source =
            if options.copy.isDefined then
              (if builtins.isString config.copy then pkgs.writeText name config.copy else config.copy)
            else if options.weakCopy.isDefined then
              (if builtins.isString config.weakCopy then pkgs.writeText name config.weakCopy else config.weakCopy)
            else if options.link.isDefined then
              (if builtins.isString config.link then pkgs.writeText name config.link else config.link)
            else null;
        };
    }
  ));
in
{
  inherit fileType ownerRefType;
}
