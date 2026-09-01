# Test-only age key

`test-age-key.txt` is a throwaway age keypair generated solely for this test suite
(`age-keygen`, public key `age1nm3zs7qfsdr9glctadw5k2nmq45uezvcwpdjecfx7k5rectxcdlqntq4j2`). It
encrypts nothing but the fixtures under `../fixtures/`, which contain placeholder values only
("test-newt-client-secret", etc.) -- never real secrets. It is intentionally committed so the
VM test can decrypt those fixtures at activation time and assert on the result.

Never point a real `sops.age.keyFile` at this key, and never encrypt real secrets with its
public key.
