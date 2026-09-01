# Small pure(ish) helpers shared across the nixos-files modules.
#
# `pkgs` is only required for the yaml-reading helpers (`fromYAML`, `sopsKeys` with a
# yaml-format file) since converting yaml -> json requires a derivation build. Callers
# that only need `fromJSON`/`ownerSecretId` may pass `pkgs = null`.
{ lib, pkgs ? null }:
{
  # Derive a short, stable, filesystem-safe id from a file's target path. Used to namespace
  # the internal `_files-owner/<id>/{user,group}` secrets generated for secretRef-backed
  # ownership so two entries never collide even if their targets differ only slightly.
  ownerSecretId = target: builtins.substring 0 12 (builtins.hashString "sha256" target);

  fromJSON = jsonFile: builtins.fromJSON (builtins.readFile jsonFile);

  fromYAML = yamlFile:
    let
      json = pkgs.runCommand "converted.json" { } ''
        ${lib.getExe pkgs.yj} < ${yamlFile} > $out
      '';
    in
    builtins.fromJSON (builtins.readFile json);

  # Read the "/"-joined leaf key paths declared in a sops-encrypted yaml/json file, optionally
  # filtered to those under the given "/"-namespaced prefix. sops-install-secrets' `key` field
  # treats "/" as a path separator into nested maps (not a literal character in a flat key --
  # see recurseSecretKey in sops-install-secrets/main.go), so the source file must use genuine
  # YAML/JSON nesting (e.g. `nginx: { certs: { "server.crt": ENC[...]; }; };`) and this walks
  # that structure to enumerate the resulting leaf paths. Sops never encrypts keys, only leaf
  # values, so this never touches ciphertext or plaintext secret content -- safe to evaluate at
  # Nix eval time.
  sopsKeys = { sopsFile, format ? "yaml", prefix ? "" }:
    let
      decoded =
        if format == "json"
        then builtins.fromJSON (builtins.readFile sopsFile)
        else
          let
            json = pkgs.runCommand "converted.json" { } ''
              ${lib.getExe pkgs.yj} < ${sopsFile} > $out
            '';
          in
          builtins.fromJSON (builtins.readFile json);

      # Recursively walk nested attrsets, collecting "/"-joined paths to every leaf (a leaf is
      # any value that isn't itself an attrset, e.g. the ENC[...] string or sops metadata leaf).
      walk = path: node:
        if builtins.isAttrs node then
          lib.concatLists (lib.mapAttrsToList
            (k: v: walk (path ++ [ k ]) v)
            node)
        else
          [ (lib.concatStringsSep "/" path) ];

      keys = walk [ ] (removeAttrs decoded [ "sops" ]);
    in
    if prefix == "" then keys else lib.filter (k: lib.hasPrefix "${prefix}/" k) keys;
}
