# CLAUDE.md

nixos-files provides orchestration for seeding system and application files. It supports:
* arbitrary file and directory installation of either encrypted/decrypted or plaintext files
* templated field installation either encryption/decryption or plaintext

## Design
This project is intended to use the sops-nix project and idiomatic NixOS community patterns where
possible to orchestrate a clean clear way to handle user configuration injection including sensitive
values.
