# Declares the shared fileType submodule used by files.any/files.root/files.user/files.all.
#
# Each entry picks exactly one "engine" by setting one of:
#   - copy / weakCopy / link       (plaintext, installed via the ported activation script)
#   - encrypted.sopsFile           (single secret file, generates one sops.secrets entry)
#   - encryptedDir.sopsFile        (directory of secrets, fans out into N sops.secrets entries)
#   - template.text/.file          (rendered by sops-nix, generates one sops.templates entry)
#
# `options.X.isDefined`, used below to auto-detect which engine an entry is using, forces
# `config.X`'s value as a side effect of resolving definitions for this submodule instance.
# That's harmless for the path-typed `encrypted`/`encryptedDir` fields, but would be fatal for
# `template.text`, which may interpolate `config.sops.placeholder."..."` -- forcing it here
# would recurse, since sops.placeholder is derived (transitively, through sops.secrets, built by
# collect.nix from every entry's `_engine`) from the very entries this isDefined check is trying
# to classify. `template` is therefore declared as `mkOption { type = nullOr (submodule {...}); }`
# rather than a bare options group like `encrypted`/`encryptedDir`, and classification below
# checks `config.template != null` (a cheap WHNF/null check) rather than
# `options.template.text.isDefined` or even `options.template.isDefined` -- the latter was
# tried and verified (against nixpkgs' module system) to spuriously read `true` whenever *any*
# sibling option on the same entry (e.g. `copy`) has a definition, even with `template` itself
# completely untouched. `config.template != null` does not have that problem and, since checking
# an attrset for non-null-ness doesn't force its nested keys, still never forces `text`.
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

        # Wrapped in its own submodule (see header comment) so that classifying this entry as
        # the template engine never forces `text`'s value.
        template = lib.mkOption {
          type = nullOr (submodule {
            options = {
              text = lib.mkOption {
                type = nullOr lines;
                default = null;
                description = ''
                  Template text, mixing ordinary Nix-eval-time text with references to
                  config.sops.placeholder for secret values. Rendered by sops-nix at activation
                  time. Ignored if `file` is also set.
                '';
              };
              file = lib.mkOption {
                type = nullOr path;
                default = null;
                description = ''
                  Path to template text, as an alternative to inline `text`. Takes precedence
                  over `text` if both are set (matches sops-nix's own
                  sops.templates.<name>.file/.content precedence).
                '';
              };
            };
          });
          default = null;
          description = ''
            Renders via sops-nix's template engine (kind=template): substitutes any
            config.sops.placeholder references in `text`/`file` and installs the result.
            Exactly one of `text`/`file` should be set.
          '';
        };

        # -- internal, computed --
        _target = lib.mkOption {
          type = str;
          internal = true;
          description = "Absolute destination path: prefix + attribute name. Not settable directly.";
        };

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
          type = enum [ "plaintext" "encrypted" "encryptedDir" "template" ];
          internal = true;
          description = "Which engine this entry is installed through.";
        };
      };

      config =
        let
          # `template`'s own `options.template.isDefined` is unreliable here: verified against
          # nixpkgs' module system that for a `nullOr (submodule {...})`-typed option nested
          # inside another submodule, `isDefined` can spuriously read true merely because a
          # *sibling* option (e.g. `copy`) has a definition, even when `template` itself was
          # never touched. `config.template != null` is the reliable substitute -- also verified
          # not to force `template.text`'s value (checking an attrset for non-null-ness is a
          # cheap WHNF check; the nested `text` thunk stays lazy either way).
          templateSet = config.template != null;

          # Exactly one install mechanism may be set per entry -- _kind/source below each pick a
          # different one via differing precedence if more than one is set, so silently mixing
          # e.g. copy+link would install with mismatched kind/source rather than erroring.
          setMechanisms = lib.filter (m: m.isDefined) [
            { name = "copy"; isDefined = options.copy.isDefined; }
            { name = "weakCopy"; isDefined = options.weakCopy.isDefined; }
            { name = "link"; isDefined = options.link.isDefined; }
            { name = "encrypted.sopsFile"; isDefined = options.encrypted.sopsFile.isDefined; }
            { name = "encryptedDir.sopsFile"; isDefined = options.encryptedDir.sopsFile.isDefined; }
            { name = "template"; isDefined = templateSet; }
          ];
          tooMany = lib.length setMechanisms > 1;
        in
        {
          _target =
            if requireAbsolute && !(lib.hasPrefix "/" name) then
              throw "files.any.\"${name}\" must be an absolute path starting with \"/\" (e.g. files.any.\"/etc/asound.conf\")"
            else "${prefix}${name}";

          _engine =
            if tooMany then
              throw "files.*.\"${name}\" sets more than one install mechanism (${lib.concatMapStringsSep ", " (m: m.name) setMechanisms}) -- set exactly one of copy/weakCopy/link/encrypted.sopsFile/encryptedDir.sopsFile/template"
            else if options.encrypted.sopsFile.isDefined then "encrypted"
            else if options.encryptedDir.sopsFile.isDefined then "encryptedDir"
            else if templateSet then "template"
            else "plaintext";

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
