# Same as user-from-secret.nix, but sourcing passwordHashSecretRef instead of passwordSecretRef
# -- the sops file holds an already-hashed password (e.g. from `mkpasswd -m sha-512`), so the
# plaintext password is never decrypted to disk at all, even transiently.
#
# The plaintext used to generate the hash in examples/secrets.enc.yaml (users/user2/passwordHash)
# is "example-svc-password", for logging in when testing this example in a VM.
#---------------------------------------------------------------------------------------------------
{ ... }:
{
  secret.users."svc-account2" = {
    sopsFile = ./secrets.enc.yaml;
    userSecretRef = "users/user2/name";
    groupSecretRef = "users/user2/group";
    passwordHashSecretRef = "users/user2/passwordHash";
    isNormalUser = true;
    uid = 1501;
  };
}
