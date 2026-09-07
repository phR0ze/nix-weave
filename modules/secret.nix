# `secret.ref` -- read-only alias for sops-nix's own `sops.placeholder`, so template content
# can reference config.secret.ref."<key>" instead of reaching into sops.placeholder directly,
# keeping every user-facing reference inside the secret.* namespace. Works for any
# config.sops.secrets entry regardless of how it was registered (secret.templates.<name>.secrets,
# files.any's encrypted engine, or sops.secrets directly) -- sops-nix itself generates one
# placeholder per sops.secrets entry once config.sops.templates is non-empty (see sops-nix's
# modules/sops/templates/default.nix), and this just exposes that same attrset under secret.*.
#---------------------------------------------------------------------------------------------------
{ config, lib, ... }:
{
  options.secret.ref = lib.mkOption {
    type = lib.types.attrsOf (lib.types.mkOptionType {
      name = "coercibleToString";
      description = "value that can be coerced to string";
      check = lib.strings.isConvertibleWithToString;
      merge = lib.mergeEqualOption;
    });
    readOnly = true;
    description = ''
      Read-only alias for config.sops.placeholder -- reference a secret's placeholder value
      (for use inside secret.templates content/file) as config.secret.ref."<key>" instead of
      config.sops.placeholder."<key>". Works for any config.sops.secrets entry, however it was
      registered.
    '';
  };

  config.secret.ref = config.sops.placeholder;
}
