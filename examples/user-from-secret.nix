# User/group created from a secret -- neither the account nor group name appears in cleartext
# in the Nix store or git. <name> ("svc-account" below) is just an internal identifier, not the
# real account name -- see modules/user-from-secret-type.nix for why.
#
# Otherwise this behaves like a normal users.users.<name> entry: isNormalUser, uid, extraGroups
# (into an already-declared plain group), and an initial password all work the same way -- the
# password is just sourced from a secret too, like the user/group names.
#---------------------------------------------------------------------------------------------------
{ ... }:
{
  # Already-declared, plain (non-secret) group for supplementary membership -- extraGroups can
  # only reference groups that exist by the time this activation script runs.
  users.groups.shared = { };

  users.fromSecret."svc-account" = {
    sopsFile = ./secrets.enc.yaml;
    userSecretRef = "provisioned/svcUsername";
    groupSecretRef = "provisioned/svcGroupname"; # private group, name also kept out of cleartext
    passwordSecretRef = "provisioned/svcPassword";
    isNormalUser = true;
    uid = 1500;
    extraGroups = [ "shared" ];
  };
}
