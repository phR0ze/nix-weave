# Declares the submodule type for secret.files -- the standalone namespace for the encrypted/
# encryptedDir engines (see secrets.nix/secrets-dir.nix), split out of the shared fileType
# submodule (file-type.nix) so files.any/root/user/all stay plaintext-only. Membership here is
# unambiguous by construction, mirroring how secret.templates is its own namespace
# (template-type.nix) rather than a field bolted onto fileType.
#
# sopsFile is one shared, top-level field -- there's no need to nest it under a per-engine
# encrypted/encryptedDir block the way file-type.nix's shared fileType submodule once needed to
# (that nesting existed only to disambiguate the encrypted engines from copy/weakCopy/link and
# from each other; this namespace has nothing else in it). Instead:
#   - `prefix` unset (single-file mode): `key` (defaulting to the attribute name) looks up one
#     leaf value in sopsFile, generating one sops.secrets entry.
#   - `prefix` set, even to "" (directory-fanout mode): sopsFile's nesting under that "/"-
#     namespaced prefix mirrors a directory tree, fanned out into one sops.secrets entry per
#     leaf. `key` is meaningless here (each leaf's own key comes from the file structure
#     instead) -- setting both `key` and `prefix` on one entry is a mutually-exclusive error.
#
# `key`/`prefix` deliberately have NO default, same reasoning as file-type.nix's copy/weakCopy/
# link: `options.X.isDefined` is true whenever a default is declared (even `default = null`)
# regardless of whether the caller actually set it, so omitting the default is what keeps
# isDefined meaningful as "did the caller set this". `_key`/`_prefix` below are the always-safe,
# already-resolved mirrors external modules (secrets.nix/secrets-dir.nix) actually read.
#
# The attribute name is a sops-nix identifier, not necessarily an install path: given without a
# leading "/" it doubles as the default sops key lookup and the install path defaults to
# sops-nix's own "/run/secrets/<name>" convention -- give an absolute name instead to override
# and install at that literal path, exactly like files.any's old encrypted/encryptedDir behavior.
#
# user/group are plain strings (unlike fileType's ownerRefType) -- secretRef-based owner
# resolution is plaintext-only (see secret-owner.nix) and was never actually wired for these
# engines; there's no point advertising a capability that silently falls back to "root".
#---------------------------------------------------------------------------------------------------
{ lib }:
with lib.types; attrsOf (submodule (
  { name, config, options, ... }: {
    options = {
      enable = lib.mkOption {
        type = bool;
        default = true;
        description = "Whether this entry should be installed.";
      };

      user = lib.mkOption {
        type = str;
        default = "root";
        description = "Owner of the decrypted file(s).";
      };

      group = lib.mkOption {
        type = str;
        default = "root";
        description = "Group of the decrypted file(s).";
      };

      dirmode = lib.mkOption {
        type = str;
        default = "0755";
        description = "Mode of any directories created to hold this entry.";
      };

      filemode = lib.mkOption {
        type = str;
        default = "0400";
        description = "Mode of the installed file(s).";
      };

      sopsFile = lib.mkOption {
        type = nullOr path;
        description = ''
          sops-encrypted file containing this entry's value (single-file mode), or whose
          nesting mirrors a directory tree under `prefix` (directory-fanout mode, when `prefix`
          is set).
        '';
      };

      key = lib.mkOption {
        type = nullOr str;
        description = ''
          Single-file mode only: key within sopsFile ("/" navigates into nested maps, per
          sops-install-secrets). Defaults to the attribute name. Mutually exclusive with
          `prefix`.
        '';
      };

      format = lib.mkOption {
        type = enum [ "yaml" "json" "binary" "dotenv" "ini" ];
        default = "yaml";
        description = "Single-file mode only: format of sopsFile.";
      };

      prefix = lib.mkOption {
        type = str;
        description = ''
          Directory-fanout mode only: only keys under this "/"-namespaced prefix are installed
          into target. Setting this at all (even to "") selects directory-fanout mode instead of
          single-file mode -- mutually exclusive with `key`.
        '';
      };

      # -- read-only, computed --
      path = lib.mkOption {
        type = str;
        description = ''
          Absolute destination path -- mirrors config.sops.secrets."<name>".path. If the
          attribute name starts with "/" this is that literal path (overriding sops-nix's
          default); otherwise it defaults to sops-nix's own "/run/secrets/<name>" convention.
        '';
      };

      # -- internal, computed --
      _id = lib.mkOption {
        type = str;
        internal = true;
        description = "The raw attribute name, before any path resolution.";
      };

      _usesDefaultSopsPath = lib.mkOption {
        type = bool;
        internal = true;
        description = ''
          True when the attribute name has no leading "/" -- path is then sops-nix's own
          default rather than an explicit override, so secrets.nix/secrets-dir.nix must omit
          `path` from the generated sops.secrets entry (letting sops-nix compute it).
        '';
      };

      _engine = lib.mkOption {
        type = enum [ "encrypted" "encryptedDir" ];
        internal = true;
        description = "Which engine this entry is installed through.";
      };

      _key = lib.mkOption {
        type = nullOr str;
        internal = true;
        description = "key if the caller set it, else null -- safe to force unconditionally.";
      };

      _prefix = lib.mkOption {
        type = str;
        internal = true;
        description = "prefix if the caller set it, else \"\" -- safe to force unconditionally.";
      };
    };

    config =
      let
        usesDefaultSopsPath = !(lib.hasPrefix "/" name);
      in
      {
        _engine =
          if !options.sopsFile.isDefined then
            throw "secret.files.\"${name}\" must set sopsFile"
          else if options.prefix.isDefined && options.key.isDefined then
            throw "secret.files.\"${name}\" sets both key (single-file mode) and prefix (directory-fanout mode) -- set only one"
          else if options.prefix.isDefined then "encryptedDir"
          else "encrypted";

        _id = name;

        _usesDefaultSopsPath = usesDefaultSopsPath;

        _key = if options.key.isDefined then config.key else null;

        _prefix = if options.prefix.isDefined then config.prefix else "";

        path = if usesDefaultSopsPath then "/run/secrets/${name}" else name;
      };
  }
))
