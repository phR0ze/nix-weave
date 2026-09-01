# NixOS VM test exercising every nixos-files engine end-to-end: plaintext copy/link
# fanned out across files.any/root/user/all, sops-nix single-file and directory decryption,
# owner-from-secret resolution, templated (mixed plaintext + secret) content, and a system
# user/group created from decrypted secret values. Decrypts
# real (test-only, see keys/README.md) sops fixtures at activation time rather than mocking
# sops-nix, since the whole point is to prove the generated sops.secrets/sops.templates wiring
# actually decrypts and lands at the right path/mode/owner.
#---------------------------------------------------------------------------------------------------
{ pkgs, nixos-files }:
pkgs.testers.runNixOSTest {
  name = "nixos-files";

  nodes.machine = { config, ... }: {
    imports = [ nixos-files ];

    sops.age.keyFile = "/etc/nixos-files-test-key.txt";
    environment.etc."nixos-files-test-key.txt" = {
      source = ./keys/test-age-key.txt;
      mode = "0400";
    };

    users.groups.alice = { };
    users.users.alice = { isNormalUser = true; group = "alice"; home = "/home/alice"; };
    users.groups.bob = { };
    users.users.bob = { isNormalUser = true; group = "bob"; home = "/home/bob"; };
    users.groups.caddy = { };
    users.users.caddy = { isSystemUser = true; group = "caddy"; };
    users.groups.testsvc = { };
    users.users.testsvc = { isSystemUser = true; group = "testsvc"; };

    # -- plaintext: files.root / files.any (string content via copy) --
    files.root.".dircolors".copy = "TERM *256color\n";
    files.any."/etc/example/hello".copy = "hello from nixos-files\n";

    # -- plaintext: files.user / files.all, fanned out per real user --
    files.user.".config/example.conf".copy = "example=1\n";
    files.all.".motd".copy = "welcome\n";

    # -- plaintext: whole directory installed as a readonly symlink --
    files.user.".config/menus".link = ../examples/include/xfce-menus;

    # -- plaintext: single file force-copied on every switch --
    files.any."/opt/svc/data-copy" = {
      copy = ../examples/include/svc/data;
    };

    # -- encrypted: single file, decrypted straight to target by sops-nix --
    files.any."/etc/newt/client-secret" = {
      encrypted = { sopsFile = ./fixtures/secrets.enc.yaml; key = "newt/clientSecret"; };
      filemode = "0400";
    };

    # -- encrypted: directory fanned out into one sops.secrets entry per leaf --
    files.any."/etc/nginx/certs" = {
      encryptedDir = { sopsFile = ./fixtures/certs.enc.yaml; prefix = "nginx/certs"; };
      filemode = "0400";
    };

    # -- owner resolved from a decrypted secret, never appearing in cleartext config --
    files.any."/opt/svc/data" = {
      copy = ../examples/include/svc/data;
      user = { secretRef = "provisioned/svcUser"; sopsFile = ./fixtures/secrets.enc.yaml; };
    };

    # -- templated file: mixed plaintext + sops placeholder --
    files.any."/run/caddy/cloudflare.env" = {
      user = "caddy";
      group = "caddy";
      filemode = "0400";
      template.text = ''
        CF_ZONE=example.com
        CF_API_TOKEN=${config.sops.placeholder."caddy/cloudflareApiToken"}
      '';
    };
    sops.secrets."caddy/cloudflareApiToken".sopsFile = ./fixtures/secrets.enc.yaml;

    # -- already-declared plain group for users.fromSecret's extraGroups below --
    users.groups.shared = { };

    # -- user/group created at activation, names only known after sops-nix decrypts them, with
    # isNormalUser/uid/extraGroups/passwordSecretRef exercising parity with users.users.<name> --
    users.fromSecret."secret-account" = {
      sopsFile = ./fixtures/secrets.enc.yaml;
      userSecretRef = "provisioned/secretUsername";
      groupSecretRef = "provisioned/secretGroupname";
      passwordSecretRef = "provisioned/secretPassword";
      isNormalUser = true;
      uid = 2500;
      extraGroups = [ "shared" ];
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("plain text file via files.root / files.any"):
        machine.succeed("test \"$(cat /root/.dircolors)\" = 'TERM *256color'")
        machine.succeed("stat -c%U:%G:%a /root/.dircolors | grep -qx 'root:root:644'")
        machine.succeed("test \"$(cat /etc/example/hello)\" = 'hello from nixos-files'")

    with subtest("plain text file via files.user, fanned out per real user"):
        machine.succeed("test \"$(cat /home/alice/.config/example.conf)\" = 'example=1'")
        machine.succeed("stat -c%U /home/alice/.config/example.conf | grep -qx alice")
        machine.succeed("test \"$(cat /home/bob/.config/example.conf)\" = 'example=1'")
        machine.succeed("stat -c%U /home/bob/.config/example.conf | grep -qx bob")

    with subtest("plain text file via files.all, root plus every real user"):
        for path, owner in [("/root/.motd", "root"), ("/home/alice/.motd", "alice"), ("/home/bob/.motd", "bob")]:
            machine.succeed(f"test \"$(cat {path})\" = 'welcome'")
            machine.succeed(f"stat -c%U {path} | grep -qx {owner}")

    with subtest("directory installed via the link engine, one symlink per leaf file"):
        machine.succeed("test -d /home/alice/.config/menus && test ! -L /home/alice/.config/menus")
        machine.succeed("test -L /home/alice/.config/menus/menu.xml")
        machine.succeed("grep -q 'placeholder menu file' /home/alice/.config/menus/menu.xml")

    with subtest("single file installed via copy (owned, force-overwritten)"):
        machine.succeed("grep -q 'placeholder service data file' /opt/svc/data-copy")

    with subtest("sops-nix decrypts a single encrypted file at activation"):
        machine.succeed("test \"$(cat /etc/newt/client-secret)\" = 'test-newt-client-secret'")
        machine.succeed("stat -L -c%a /etc/newt/client-secret | grep -qx 400")

    with subtest("sops-nix fans an encrypted directory out into one secret per leaf"):
        machine.succeed("test \"$(cat /etc/nginx/certs/server.crt)\" = 'test-server-crt-content'")
        machine.succeed("test \"$(cat /etc/nginx/certs/server.key)\" = 'test-server-key-content'")
        machine.succeed("stat -L -c%a /etc/nginx/certs/server.crt | grep -qx 400")

    with subtest("owner resolved from a decrypted secret, never appearing in cleartext config"):
        machine.succeed("stat -c%U /opt/svc/data | grep -qx testsvc")

    with subtest("templated file mixes plaintext and a sops placeholder"):
        machine.succeed("grep -q '^CF_ZONE=example.com$' /run/caddy/cloudflare.env")
        machine.succeed("grep -q '^CF_API_TOKEN=test-cf-api-token$' /run/caddy/cloudflare.env")
        machine.succeed("stat -L -c%U:%G:%a /run/caddy/cloudflare.env | grep -qx 'caddy:caddy:400'")

    with subtest("user/group created at activation from decrypted secrets, with users.users parity"):
        machine.succeed("getent group secretgrp")
        machine.succeed("id secretsvc")
        machine.succeed("test \"$(id -gn secretsvc)\" = 'secretgrp'")
        machine.succeed("test \"$(id -u secretsvc)\" = '2500'")
        machine.succeed("id -nG secretsvc | grep -qw shared")
        machine.succeed("getent passwd secretsvc | cut -d: -f7 | grep -q '/bin/bash$'")
        machine.succeed("test -d /home/secretsvc")
        machine.succeed("stat -c%U:%a /home/secretsvc | grep -qx 'secretsvc:700'")
        machine.succeed("passwd -S secretsvc | grep -q '^secretsvc P'")
        machine.succeed("grep -qE '^secretsvc:[0-9]+:65536$' /etc/subuid")
        machine.succeed("grep -qE '^secretsvc:[0-9]+:65536$' /etc/subgid")

    with subtest("re-running activation is idempotent"):
        machine.succeed("/run/current-system/activate")
        machine.succeed("test \"$(cat /etc/newt/client-secret)\" = 'test-newt-client-secret'")
        machine.succeed("test -s /opt/svc/data-copy")
        machine.succeed("id secretsvc")
  '';
}
