# `files.secrets` -- standalone namespace for the encrypted/encryptedDir engines (see
# secret-type.nix), split out of the shared fileType submodule so files.any/root/user/all stay
# plaintext-only. This module owns the option declaration and the `encrypted` (single secret
# file) engine, generating one sops.secrets entry per entry, placed directly at the entry's
# target path -- decryption/placement/permissions are 100% delegated to sops-nix, no bespoke
# activation code. secrets-dir.nix handles the `encryptedDir` engine, reading from this same
# config.files.secrets, exactly like templates.nix/tmpfiles.nix consume config.files.templates
# without re-declaring it.
#---------------------------------------------------------------------------------------------------
{ config, lib, ... }:
let
  secretType = import ./secret-type.nix { inherit lib; };

  entries = lib.filter (e: e._engine == "encrypted")
    (lib.attrValues (lib.filterAttrs (_: e: e.enable) config.files.secrets));

  toSecret = entry: {
    # A bare (no leading "/") identifier is used verbatim as the sops.secrets name -- entry.path
    # is then just sops-nix's own default, not a real override (see _usesDefaultSopsPath in
    # secret-type.nix), so `path` below is omitted rather than passed through, letting sops-nix
    # compute the identical default itself.
    name = if entry._usesDefaultSopsPath then entry._id else lib.removePrefix "/" entry.path;
    value = {
      sopsFile = entry.encrypted.sopsFile;
      format = entry.encrypted.format;
      # sops-install-secrets treats "/" in `key` as a path separator into nested maps (not a
      # literal character), so an explicit target's default must not be the full
      # (slash-containing) path -- fall back to just its last path component instead. A bare
      # identifier has no such ambiguity: it's used as-is, exactly like sops-nix's own default.
      key =
        if entry.encrypted.key != null then entry.encrypted.key
        else if entry._usesDefaultSopsPath then entry._id
        else baseNameOf entry.path;
      owner = entry.user;
      group = entry.group;
      mode = entry.filemode;
    } // lib.optionalAttrs (!entry._usesDefaultSopsPath) { path = entry.path; };
  };
in
{
  options.files.secrets = lib.mkOption {
    type = secretType;
    default = { };
    description = ''
      Files decrypted straight from a sops-encrypted source via sops-nix's own sops.secrets,
      standalone from files.any/root/user/all (which are plaintext-only). The attribute name is
      a sops-nix identifier: given without a leading "/" it doubles as the default sops key
      lookup, and the install path defaults to sops-nix's own "/run/secrets/<name>" convention;
      given with a leading "/" it's used as a literal install path instead, overriding that
      default. Exactly one of encrypted.sopsFile/encryptedDir.sopsFile must be set.
    '';
    example = ''
      files.secrets."newt/clientSecret".encrypted.sopsFile = ./secrets.enc.yaml;
    '';
  };

  config = lib.mkIf (entries != [ ]) {
    sops.secrets = lib.listToAttrs (map toSecret entries);
  };
}
