# Single encrypted file -- decrypted only at activation, never in the store or git.
#---------------------------------------------------------------------------------------------------
{ ... }:
{
  files.root."newt-secret" = {
    target = "/etc/newt/client-secret";
    encrypted = { sopsFile = ./secrets.enc.yaml; key = "newt/clientSecret"; };
    filemode = "0400";
  };
}
