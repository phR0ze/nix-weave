# Declares the shared fileType submodule used by files.any/files.root/files.user/files.all.
#
# Each entry picks exactly one "engine" by setting one of:
#   - copy / weakCopy / link       (plaintext, installed via the ported activation script)
#   - encrypted.sopsFile           (single secret file, generates one sops.secrets entry)
#   - encryptedDir.sopsFile        (directory of secrets, fans out into N sops.secrets entries)
#
# Rendered (sops-nix template) content lives in its own standalone `files.templates.<name>`
# namespace instead (see template-type.nix/templates.nix) -- membership there is unambiguous by
# construction, unlike the engines here which all share one submodule and must be disambiguated
# via `options.X.isDefined`.
#
# `options.X.isDefined`, used below to auto-detect which engine an entry is using, forces
# `config.X`'s value as a side effect of resolving definitions for this submodule instance.
# That's harmless for the path-typed `encrypted`/`encryptedDir`/`copy`/`weakCopy`/`link` fields.
#
# `user`/`group` normally take a plain string, but may instead take `{ secretRef; sopsFile; }`
# to resolve the actual owner name from a sops secret at activation time (plaintext engine only).
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
        type = nullOr path;
        default = null;
        description = ''
          sops file containing secretRef. Defaults to this entry's own encrypted.sopsFile if
          set; must be given explicitly on plain copy/weakCopy/link entries.
        '';
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

        # NOTE: copy/weakCopy/link/encrypted.sopsFile/encryptedDir.sopsFile deliberately have NO
        # `default`. `_engine`/`_kind`/`source` below are computed from `options.*.isDefined`
        # rather than `config.* != null` -- and `isDefined` is true whenever a `default` is
        # declared, even `default = null`, regardless of whether the caller actually set it.
        # Omitting the default keeps `isDefined` meaningful.

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

        encrypted = {
          sopsFile = lib.mkOption {
            type = nullOr path;
            description = "sops-encrypted file containing this entry's value.";
          };
          key = lib.mkOption {
            default = null;
            type = nullOr str;
            description = ''
              Key within sopsFile ("/" navigates into nested maps, per sops-install-secrets).
              Defaults to the last path component of target.
            '';
          };
          format = lib.mkOption {
            type = enum [ "yaml" "json" "binary" "dotenv" "ini" ];
            default = "yaml";
            description = "Format of sopsFile.";
          };
        };

        encryptedDir = {
          sopsFile = lib.mkOption {
            type = nullOr path;
            description = ''
              sops-encrypted yaml/json file whose nesting mirrors the directory tree (one leaf
              per file, e.g. nginx.certs."server.crt"). Fanned out into one sops.secrets entry
              per leaf, keyed by its "/"-joined path, at activation time.
            '';
          };
          prefix = lib.mkOption {
            default = "";
            type = str;
            description = "Only keys under this \"/\"-namespaced prefix are installed into target.";
          };
        };

        # -- read-only, computed --
        path = lib.mkOption {
          type = str;
          description = ''
            Absolute destination path: prefix + attribute name. Not settable directly -- mirrors
            config.sops.secrets."<name>".path, so this can be referenced as an input elsewhere
            (e.g. a systemd unit's EnvironmentFile) once the entry is installed.

            files.any's encrypted/encryptedDir entries are the one exception: their attribute
            name may instead be a bare sops-nix identifier (no leading "/"), in which case this
            defaults to sops-nix's own "/run/secrets/<name>" convention rather than requiring an
            explicit path up front -- see _usesDefaultSopsPath.
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

        _engine = lib.mkOption {
          type = enum [ "plaintext" "encrypted" "encryptedDir" ];
          internal = true;
          description = "Which engine this entry is installed through.";
        };

        _id = lib.mkOption {
          type = str;
          internal = true;
          description = "The raw attribute name, before any prefix/path resolution.";
        };

        _usesDefaultSopsPath = lib.mkOption {
          type = bool;
          internal = true;
          description = ''
            True only for a files.any encrypted/encryptedDir entry whose attribute name was
            given without a leading "/" -- `path` is then sops-nix's own default rather than an
            explicit override, so secrets.nix/secrets-dir.nix must omit `path` from the
            generated sops.secrets entry (letting sops-nix compute it) instead of passing it
            through verbatim.
          '';
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
            { name = "encrypted.sopsFile"; isDefined = options.encrypted.sopsFile.isDefined; }
            { name = "encryptedDir.sopsFile"; isDefined = options.encryptedDir.sopsFile.isDefined; }
          ];
          tooMany = lib.length setMechanisms > 1;

          engine =
            if tooMany then
              throw "files.*.\"${name}\" sets more than one install mechanism (${lib.concatMapStringsSep ", " (m: m.name) setMechanisms}) -- set exactly one of copy/weakCopy/link/encrypted.sopsFile/encryptedDir.sopsFile"
            else if options.encrypted.sopsFile.isDefined then "encrypted"
            else if options.encryptedDir.sopsFile.isDefined then "encryptedDir"
            else "plaintext";

          # Only files.any's encrypted/encryptedDir entries may skip the leading "/" -- plaintext
          # entries (copy/weakCopy/link) always need a real install path, and files.root/user/all
          # are prefix-relative by design so "absolute or not" doesn't apply to them.
          isSopsEngine = engine == "encrypted" || engine == "encryptedDir";
          usesDefaultSopsPath = requireAbsolute && isSopsEngine && !(lib.hasPrefix "/" name);
        in
        {
          path =
            if lib.hasPrefix "/" name then "${prefix}${name}"
            else if usesDefaultSopsPath then
              # Mirrors sops-nix's own sops.secrets."<name>".path default -- secrets.nix/
              # secrets-dir.nix likewise omit `path` in this case so sops-nix computes the exact
              # same value, rather than risking drift by duplicating its logic independently.
              "/run/secrets/${name}"
            else if requireAbsolute then
              throw "files.any.\"${name}\" must be an absolute path starting with \"/\" (e.g. files.any.\"/etc/asound.conf\") -- an encrypted/encryptedDir entry may instead omit the leading \"/\" to use the name as a sops-nix identifier, defaulting to /run/secrets/<name>"
            else "${prefix}${name}";

          _id = name;

          _usesDefaultSopsPath = usesDefaultSopsPath;

          _engine = engine;

          _kind = if options.link.isDefined then "link" else "copy";

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
