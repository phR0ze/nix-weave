# User/group created from a secret -- neither the account nor group name appears in cleartext
# in the Nix store or git. <name> ("svc-account" below) is just an internal identifier, not the
# real account name -- see modules/user-from-secret-type.nix for why.
#---------------------------------------------------------------------------------------------------
{ ... }:
{
  users.fromSecret."svc-account" = {
    sopsFile = ./secrets.enc.yaml;
    userSecretRef = "provisioned/svcUsername";
    groupSecretRef = "provisioned/svcGroupname";
  };
}
