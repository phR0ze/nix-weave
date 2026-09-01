# Owner resolved from a secret at activation time -- the account name itself never appears
# in cleartext in the Nix store or git.
#---------------------------------------------------------------------------------------------------
{ ... }:
{
  files.root."svc-file" = {
    target = "/opt/svc/data";
    copy = ./include/svc/data;
    user = { secretRef = "provisioned/svcUser"; sopsFile = ./secrets.enc.yaml; };
  };
}
