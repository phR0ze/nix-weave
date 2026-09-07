# CLAUDE.md

nix-weave provides orchestration for seeding system and application files. It supports:
* arbitrary file and directory installation of either encrypted/decrypted or plaintext files
* templated field installation either encryption/decryption or plaintext

## Design
This project is intended to use the sops-nix project and idiomatic NixOS community patterns where
possible to orchestrate a clean clear way to handle user configuration injection including sensitive
values.

## Secrets/sops key for examples and tests
`tests/keys/test-age-key.txt` (public key `age1nm3zs7qfsdr9glctadw5k2nmq45uezvcwpdjecfx7k5rectxcdlqntq4j2`,
documented in `tests/keys/README.md`) is the *only* age key used anywhere in this repo -- both
`examples/*.enc.yaml` and `tests/fixtures/*.enc.yaml` are encrypted for it. Always use this key
when creating or editing any encrypted fixture in `examples/` or `tests/fixtures/`, e.g.:

```sh
SOPS_AGE_KEY_FILE=tests/keys/test-age-key.txt sops edit examples/secrets.enc.yaml
SOPS_AGE_KEY_FILE=tests/keys/test-age-key.txt sops set tests/fixtures/secrets.enc.yaml '["path"]["to"]["key"]' '"value"'
```

It encrypts placeholder/example values only, never real secrets -- see `tests/keys/README.md`
for why it's intentionally committed. Never introduce a second age key for examples/tests; a
single shared key keeps every encrypted fixture in the repo editable the same way.
