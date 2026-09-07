# Declares the submodule type for files.secrets -- the standalone namespace for the encrypted/
# encryptedDir engines (see secrets.nix/secrets-dir.nix), split out of the shared fileType
# submodule (file-type.nix) so files.any/root/user/all stay plaintext-only. Membership here is
# unambiguous by construction, mirroring how files.templates is its own namespace
# (template-type.nix) rather than a field bolted onto fileType.
#
# Each entry picks exactly one engine by setting one of:
#   - encrypted.sopsFile      (single secret file, generates one sops.secrets entry)
#   - encryptedDir.sopsFile   (directory of secrets, fans out into N sops.secrets entries)
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
  { name, options, ... }: {
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
            Defaults to the attribute name.
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
    };

    config =
      let
        setMechanisms = lib.filter (m: m.isDefined) [
          { name = "encrypted.sopsFile"; isDefined = options.encrypted.sopsFile.isDefined; }
          { name = "encryptedDir.sopsFile"; isDefined = options.encryptedDir.sopsFile.isDefined; }
        ];
        tooMany = lib.length setMechanisms > 1;

        usesDefaultSopsPath = !(lib.hasPrefix "/" name);
      in
      {
        _engine =
          if tooMany then
            throw "files.secrets.\"${name}\" sets more than one install mechanism (${lib.concatMapStringsSep ", " (m: m.name) setMechanisms}) -- set exactly one of encrypted.sopsFile/encryptedDir.sopsFile"
          else if options.encrypted.sopsFile.isDefined then "encrypted"
          else if options.encryptedDir.sopsFile.isDefined then "encryptedDir"
          else throw "files.secrets.\"${name}\" must set one of encrypted.sopsFile/encryptedDir.sopsFile";

        _id = name;

        _usesDefaultSopsPath = usesDefaultSopsPath;

        path = if usesDefaultSopsPath then "/run/secrets/${name}" else name;
      };
  }
))
