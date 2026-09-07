# `files.secret` -- read-only alias for sops-nix's own `sops.placeholder`, so template content
# can reference config.files.secret."<key>" instead of reaching into sops.placeholder directly,
# keeping every user-facing reference inside the files.* namespace. Works for any
# config.sops.secrets entry regardless of how it was registered (files.templates.<name>.secrets,
# files.any's encrypted engine, or sops.secrets directly) -- sops-nix itself generates one
# placeholder per sops.secrets entry once config.sops.templates is non-empty (see sops-nix's
# modules/sops/templates/default.nix), and this just exposes that same attrset under files.*.
#---------------------------------------------------------------------------------------------------
{ config, lib, ... }:
{
  options.files.secret = lib.mkOption {
    type = lib.types.attrsOf (lib.types.mkOptionType {
      name = "coercibleToString";
      description = "value that can be coerced to string";
      check = lib.strings.isConvertibleWithToString;
      merge = lib.mergeEqualOption;
    });
    readOnly = true;
    description = ''
      Read-only alias for config.sops.placeholder -- reference a secret's placeholder value
      (for use inside files.templates content/file) as config.files.secret."<key>" instead of
      config.sops.placeholder."<key>". Works for any config.sops.secrets entry, however it was
      registered.
    '';
  };

  config.files.secret = config.sops.placeholder;
}
