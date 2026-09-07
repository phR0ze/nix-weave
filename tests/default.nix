# NixOS VM test exercising every nix-weave engine end-to-end: plaintext copy/link
# fanned out across files.any/root/user/all, sops-nix single-file and directory decryption,
# owner-from-secret resolution, templated (mixed plaintext + secret) content, and a system
# user/group created from decrypted secret values. Decrypts
# real (test-only, see keys/README.md) sops fixtures at activation time rather than mocking
# sops-nix, since the whole point is to prove the generated sops.secrets/sops.templates wiring
# actually decrypts and lands at the right path/mode/owner.
#---------------------------------------------------------------------------------------------------
{ pkgs, nix-weave }:
pkgs.testers.runNixOSTest {
  name = "nix-weave";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ nix-weave ];

    sops.age.keyFile = "/etc/nix-weave-test-key.txt";
    environment.etc."nix-weave-test-key.txt" = {
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
    files.any."/etc/example/hello".copy = "hello from nix-weave\n";

    # -- plaintext: files.user / files.all, fanned out per real user --
    files.user.".config/example.conf".copy = "example=1\n";
    files.all.".motd".copy = "welcome\n";

    # -- plaintext: whole directory installed as a readonly symlink --
    files.user.".config/menus".link = ../examples/include/xfce-menus;

    # -- plaintext: single file force-copied on every switch --
    files.any."/opt/svc/data-copy" = {
      copy = ../examples/include/svc/data;
    };

    # -- secret.files: bare (no leading "/") identifier with an explicit key override -- no
    # install path given up front, so it defaults to sops-nix's own "/run/secrets/<name>"
    # convention --
    secret.files."newt-client-secret" = {
      sopsFile = ./fixtures/secrets.enc.yaml;
      key = "newt/clientSecret";
    };

    # -- consume secret.files."newt-client-secret".path as an input elsewhere, mirroring
    # config.sops.secrets."<name>".path, to prove it resolves to the same real (defaulted) path --
    systemd.services.newt-client-secret-check = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.bash}/bin/bash -c 'cat ${config.secret.files."newt-client-secret".path} > /run/newt-client-secret-check'";
      };
    };

    # -- secret.files: bare (no leading "/") identifier -- no install path given up front, so
    # it defaults to sops-nix's own "/run/secrets/<name>" convention, with the identifier
    # doubling as the sops key lookup (both default to "newt/clientSecret") exactly like an
    # ordinary config.sops.secrets."newt/clientSecret" left at its default path --
    secret.files."newt/clientSecret".sopsFile = ./fixtures/secrets.enc.yaml;

    # -- secret.files: directory fanned out into one sops.secrets entry per leaf, bare (no
    # leading "/") identifier -- each leaf defaults to sops-nix's own "/run/secrets/<name>/<leaf>"
    # path --
    secret.files."nginx/certs" = { sopsFile = ./fixtures/certs.enc.yaml; prefix = "nginx/certs"; };

    # -- owner resolved from a decrypted secret, never appearing in cleartext config --
    files.any."/opt/svc/data" = {
      copy = ../examples/include/svc/data;
      user = { secretRef = "provisioned/svcUser"; sopsFile = ./fixtures/secrets.enc.yaml; };
    };

    # -- templated file: mixed plaintext + two sops placeholders, secrets registered inline via
    # the template's own `secrets` field rather than a separate sops.secrets block --
    secret.templates."cloudflare-env" = {
      path = "/run/caddy/cloudflare.env";   # defaults to /run/secrets/rendered/<name> like sops-nix
      user = "caddy";                       # defaults to root:root like sops-nix
      group = "caddy";
      content = ''
        CF_ZONE=${config.secret.ref."caddy/cfZone"}
        CF_API_TOKEN=${config.secret.ref."caddy/cloudflareApiToken"}
      '';
      secrets = {
        "caddy/cfZone".sopsFile = ./fixtures/secrets.enc.yaml;
        "caddy/cloudflareApiToken".sopsFile = ./fixtures/secrets.enc.yaml;
      };
    };

    # -- consume secret.templates."cloudflare-env".path as an input elsewhere, to prove it
    # resolves to the same real, rendered path rather than just round-tripping a Nix string --
    systemd.services.cloudflare-env-check = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = config.secret.templates."cloudflare-env".path;
        ExecStart = "${pkgs.bash}/bin/bash -c 'echo \"$CF_ZONE\" > /run/cloudflare-env-check-zone'";
      };
    };

    # -- already-declared plain group for secret.users's extraGroups below --
    users.groups.shared = { };

    # -- user/group created at activation, names only known after sops-nix decrypts them, with
    # isNormalUser/uid/extraGroups/passwordSecretRef exercising parity with users.users.<name> --
    secret.users."secret-account" = {
      sopsFile = ./fixtures/secrets.enc.yaml;
      userSecretRef = "provisioned/secretUsername";
      groupSecretRef = "provisioned/secretGroupname";
      passwordSecretRef = "provisioned/secretPassword";
      isNormalUser = true;
      uid = 2500;
      extraGroups = [ "shared" ];
    };

    # -- same as above, but the initial password comes pre-hashed (mkpasswd -m sha-512) via
    # passwordHashSecretRef, so the plaintext password is never decrypted to disk at all --
    secret.users."secret-hash-account" = {
      sopsFile = ./fixtures/secrets.enc.yaml;
      userSecretRef = "provisioned/secretHashUsername";
      groupSecretRef = "provisioned/secretHashGroupname";
      passwordHashSecretRef = "provisioned/secretPasswordHash";
      isNormalUser = true;
      uid = 2501;
      extraGroups = [ "shared" ];
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("plain text file via files.root / files.any"):
        machine.succeed("test \"$(cat /root/.dircolors)\" = 'TERM *256color'")
        machine.succeed("stat -c%U:%G:%a /root/.dircolors | grep -qx 'root:root:644'")
        machine.succeed("test \"$(cat /etc/example/hello)\" = 'hello from nix-weave'")

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

    with subtest("secret.files.\"newt-client-secret\".path resolves to the real decrypted file when used as an input elsewhere"):
        machine.wait_for_unit("newt-client-secret-check.service")
        machine.succeed("test \"$(cat /run/newt-client-secret-check)\" = 'test-newt-client-secret'")

    with subtest("secret.files.\"newt/clientSecret\" (bare identifier, no leading /) defaults to sops-nix's own /run/secrets/<name> path"):
        machine.succeed("test \"$(cat /run/secrets/newt/clientSecret)\" = 'test-newt-client-secret'")

    with subtest("sops-nix decrypts a single encrypted file at activation"):
        machine.succeed("test \"$(cat /run/secrets/newt-client-secret)\" = 'test-newt-client-secret'")
        machine.succeed("stat -L -c%a /run/secrets/newt-client-secret | grep -qx 400")

    with subtest("sops-nix fans an encrypted directory out into one secret per leaf"):
        machine.succeed("test \"$(cat /run/secrets/nginx/certs/server.crt)\" = 'test-server-crt-content'")
        machine.succeed("test \"$(cat /run/secrets/nginx/certs/server.key)\" = 'test-server-key-content'")
        machine.succeed("stat -L -c%a /run/secrets/nginx/certs/server.crt | grep -qx 400")

    with subtest("owner resolved from a decrypted secret, never appearing in cleartext config"):
        machine.succeed("stat -c%U /opt/svc/data | grep -qx testsvc")

    with subtest("templated file mixes plaintext and two sops placeholders"):
        machine.succeed("grep -q '^CF_ZONE=test-cf-zone.example.com$' /run/caddy/cloudflare.env")
        machine.succeed("grep -q '^CF_API_TOKEN=test-cf-api-token$' /run/caddy/cloudflare.env")
        machine.succeed("stat -L -c%U:%G:%a /run/caddy/cloudflare.env | grep -qx 'caddy:caddy:400'")

    with subtest("secret.templates.\"cloudflare-env\".path resolves to the real rendered file when used as an input elsewhere"):
        machine.wait_for_unit("cloudflare-env-check.service")
        machine.succeed("test \"$(cat /run/cloudflare-env-check-zone)\" = 'test-cf-zone.example.com'")

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

    with subtest("user created at activation with a pre-hashed password (passwordHashSecretRef)"):
        machine.succeed("getent group secrethashgrp")
        machine.succeed("id secrethashsvc")
        machine.succeed("test \"$(id -gn secrethashsvc)\" = 'secrethashgrp'")
        machine.succeed("test \"$(id -u secrethashsvc)\" = '2501'")
        machine.succeed("id -nG secrethashsvc | grep -qw shared")
        machine.succeed(
            "test \"$(getent shadow secrethashsvc | cut -d: -f2)\" = "
            "'$6$nJlv1.S8eP/OsYJM$9yOxieRtEqDSoaiI3Q0IXgRbnJQwKyKPk9DHj3Y9v68YUdBRXBMrYg4ElCiwmDLLiFEBfSK4YYDgC0UcIcaY60'"
        )
        machine.succeed("passwd -S secrethashsvc | grep -q '^secrethashsvc P'")

    with subtest("re-running activation is idempotent"):
        machine.succeed("/run/current-system/activate")
        machine.succeed("test \"$(cat /run/secrets/newt-client-secret)\" = 'test-newt-client-secret'")
        machine.succeed("test -s /opt/svc/data-copy")
        machine.succeed("id secretsvc")
        machine.succeed("id secrethashsvc")
  '';
}
