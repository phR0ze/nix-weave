# nix-weave

Activation-time NixOS file and secret installation leveraging [sops-nix](https://github.com/Mic92/sops-nix).

Installs arbitrary files/directories -- plaintext or encrypted -- and renders templated files
mixing plaintext and secret fields, without ever writing decrypted secret content to the Nix
store or git. Encryption/templating are thin wrappers over sops-nix's own `sops.secrets`/
`sops.templates`, which decrypt only at activation time into `/run/secrets*`. Plaintext
copy/link installation is handled by a small activation script.

### Quick links
- [Overview](#overview)
  - [Getting started](#getting-started)
  - [Install functions](#install-functions)
  - [Content type and ownership](#content-type-and-ownership)
  - [File ownership](#file-ownership)
  - [File permissions](#file-permissions)
- [Usage](#usage)
  - [Dedupe sops-nix](#dedupe-sops-nix)
  - [Plaintext files](#plaintext-files)
  - [Owner resolved from a secret](#owner-resolved-from-a-secret)
  - [Encrypted files](#encrypted-files)
    - [Encrypted file](#encrypted-file)
    - [Encrypted directory](#encrypted-directory)
  - [Templated files](#templated-files)
  - [User created from a secret](#user-created-from-a-secret)
- [Running the examples](#running-the-examples)
- [Test suite](#test-suite)
- [Backlog](#backlog)

## Overview

### Getting started
Import ***nix-weave*** and set follows for your nixpkgs

1. Modify your configuration to use nix-weave
   ```nix
   {
     inputs = {
       nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
       nix-weave.url = "github:phR0ze/nix-weave";
       nix-weave.inputs.nixpkgs.follows = "nixpkgs";
     };
   
     outputs = { nixpkgs, nix-weave, ... }: {
       nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
         modules = [
           nix-weave.nixosModules.default
           ./configuration.nix
         ];
       };
     };
   }
   ```
2. Install the age key. ***nix-weave*** defaults `sops.age.keyFile` to whichever of
   `/root/.config/sops/age/keys.txt` or `~/.config/sops/age/keys.txt` exists (mirroring sops'
   own conventional key location), so dropping the key at one of those paths is enough:
   1. Create the path on the vm `mkdir -p /root/.config/sops/age`
   2. SCP into or out from the VM from/to a known seed system to copy over `keys.txt` to that location
   3. Set permissions `chmod 400 /root/.config/sops/age/keys.txt`
   4. To use a different location instead, set `sops.age.keyFile` explicitly -- it takes priority
      over the default.

### Install functions
***nix-weave*** provides a number of different ***install functions*** for different purposes.
For every `files.<install-function>.<name>` the *name* attribute IS the install path -- there's no
separate field to set, **except `secret.templates`/`secret.files`**, where *name* is just an
identifier (mirroring sops-nix's own `sops.templates."<name>"`/`sops.secrets."<name>"`) rather
than necessarily being one. See [Templated files](#templated-files) and
[Encrypted files](#encrypted-files).

| Install function    | Description
| ------------------- | ---------------------------------------------------------------------
| `files.any`         | installs plaintext files at an arbitrary location on disk
| `files.root`        | installs plaintext files relative to `/root/`
| `files.user`        | installs plaintext files for all real users i.e. `isNormalUser = true`
| `files.all`         | installs plaintext files for both `/root/<name>` and `$HOME/<name>` for every real user
| `secret.files`      | decrypts a sops-encrypted file/directory straight to the target via sops-nix's own `sops.secrets`
| `secret.templates`  | renders a file mixing plaintext and secret fields via sops-nix's template engine
| `secret.users`      | installs a new user/group idempotently from secrets to avoid exposing PII

> [!NOTE]
> `secret.ref` (singular, [an alias for `config.sops.placeholder`](#templated-files)) and
> `secret.files` (plural, this install function) are two different options -- easy to conflate
> by name, two related but separate functions: one references a value inside template content, the
> other installs a decrypted file/directory.

Every entry also exposes a read-only `path` field with the final resolved install path -- mirroring
`config.sops.secrets."<name>".path` -- so it can be referenced as an input elsewhere in your config
(e.g. a systemd unit's `EnvironmentFile`) rather than duplicating the path as a separate string:

```nix
systemd.services.cloudflare-env-check.serviceConfig.EnvironmentFile =
  config.secret.templates."cloudflare-env".path;
```

### Content type and ownership
Ownership in this sense means who is responsible for the lifecycle of the files. If the files are
considered ***owned*** then nix-weave will manage the lifecycle and remove the file when no longer
specified in the configuration or overwrite on each activation with the specified content from the
configuration to ensure its always correct. If ***unowned*** then nix-weave will ensure the file is
installed if it doesn't exist and not touch it after that.

The various content types/modes below have a specific ownership type they evoke.
`copy`/`link` (and every `secret.files`/`secret.templates` entry) are all **owned**.
`weakCopy` is the only **unowned** case.

`copy`/`weakCopy`/`link` are `files.any`/`root`/`user`/`all`'s content types: they accept either a
***string*** or a ***path*** -- a string is rendered to a Nix store path first (not necessarily
ASCII/text, and always a single file -- a directory tree requires a path), a path (file, or whole
directory for `link`) is used directly.

| Content types   | Behavior                                                                         |
| --------------- | -------------------------------------------------------------------------------- |
| `copy`          | Force-copies the content to the target on every activation                       |
| `weakCopy`      | Copies the content to the install location if it doesn't exist                   |
| `link`          | Installs a readonly symlink at the target, pointed at the content                |

`secret.files` always takes a `sopsFile` path, decrypted straight to the target by sops-nix --
no plaintext ever touches the Nix store or git. It has no separate content-type field to set;
instead it picks one of two modes depending on whether `prefix` is set (see
[Encrypted files](#encrypted-files)):

| `secret.files` mode   | Trigger                | Behavior                                                                  |
| --------------------- | ----------------------- | -------------------------------------------------------------------------- |
| single-file            | `prefix` unset          | Decrypts a single secret value (looked up via `key`) straight to the target |
| directory-fanout       | `prefix` set (even `""`) | Decrypts a whole directory of secrets, fanning out into one target file per leaf |

### File ownership
All files default to a particular user and group owner based on which install function was used, with
the option to then override in some cases.

* `files.any` - defaults to `root:root` and ***allows for overriding user and group***
* `files.root` - defaults to `root:root` and can not be overridden
* `files.user` - defaults to the implicated user and can not be overridden
* `files.all` - defaults to the implicated user and can not be overridden
* `secret.files` - defaults to `root:root` and ***allows for overriding user and group*** (plain
  strings only -- no secretRef support, since sops-nix's own ownership fields don't support it)
* `secret.templates` - defaults to `root:root` and ***allows for overriding user and group***

The following provides examples of overridding the user and group for the ***any*** install function.

```nix
# Overridden user and group
files.any."/run/caddy/cache" = {
  copy = ../include/caddy/cache;
  user = "caddy"; group = "caddy"; filemode = "0400";
};

# Protected user and group
files.any."/opt/svc/data" = {
  copy = ../include/svc/data;
  user = { secretRef = "provisioned/svcUser"; sopsFile = ./secrets.enc.yaml; };
  group = { secretRef = "provisioned/svcGroup"; sopsFile = ./secrets.enc.yaml; };
};
```

### File permissions
All files default to `0644` and all directories default to `0755`. However you can override these
default values using the `filemode` and `dirmode` fields.

So the following will install to `$HOME/.ssh/id_ed25519` using (mode 0600) and create `$HOME/.ssh`
with `mode 0700` if it doesn't exist, both owned by the real user.

```nix
files.user.".ssh/id_ed25519" = {
  copy = ./id_ed25519;
  filemode = "0600";
  dirmode = "0700";
};
```

## Usage

### Dedupe sops-nix
If you also use sops-nix directly yourself (e.g. for `sops.secrets` unrelated to nix-weave),
you can still import `sops-nix.nixosModules.sops` in your own `modules` list -- NixOS dedupes
identical module imports automatically, but only if both resolve to the exact same sops-nix
input. Pin `nix-weave.inputs.sops-nix.follows = "sops-nix";` (alongside declaring your own
`sops-nix.url` input) to guarantee that:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    nix-weave.url = "github:phR0ze/nix-weave";
    nix-weave.inputs.nixpkgs.follows = "nixpkgs";
    nix-weave.inputs.sops-nix.follows = "sops-nix";
  };

  outputs = { nixpkgs, sops-nix, nix-weave, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        sops-nix.nixosModules.sops
        nix-weave.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

#### Plaintext files
All the install functions can be used with plaintext text inputs or files that then get packaged up
in the nix store for installation during activation time. This is a clean, simple way to seed your
system with configuration files for the system and/or users.

```nix
files.any."/etc/asound.conf".copy = "autospawn=no";             # -> /etc/asound.conf
files.root.".dircolors".copy = ../include/home/.dircolors;      # -> /root/.dircolors
files.user.".config/menus".link = ../include/xfce-menus;        # -> every real user's $HOME/.config/menus
files.all.".motd".copy = "welcome\n";                           # -> /root/.motd and every real user's $HOME/.motd
```

#### Owner resolved from a secret
When you don't want to expose the user owner or group during plaintext file installation you can use
secret references. `user` and `group` can each independently be a plain string or a `secretRef`
-- mix and match as needed:

```nix
# user only
files.any."/opt/svc/data" = {
  copy = ../include/svc/data;
  user = { secretRef = "provisioned/svcUser"; sopsFile = ./secrets.enc.yaml; };
};

# user and group
files.any."/opt/svc/data" = {
  copy = ../include/svc/data;
  user = { secretRef = "provisioned/svcUser"; sopsFile = ./secrets.enc.yaml; };
  group = { secretRef = "provisioned/svcGroup"; sopsFile = ./secrets.enc.yaml; };
};
```

#### Encrypted files
***secret.files*** is its own standalone install function (like ***secret.users***/
***secret.templates***, not a field on `files.any`/`root`/`user`/`all`, which are plaintext-only)
for content decrypted straight from a sops-encrypted source via sops-nix's own `sops.secrets`.

The attribute name is a sops-nix identifier, not necessarily an install path: give it as a bare
identifier (no leading `/`) and there's no install path to give up front -- it defaults to
sops-nix's own `/run/secrets/<name>` convention, with the identifier doubling as the sops key
lookup (both default to the same string), exactly like an ordinary `config.sops.secrets."<name>"`
left at its default path. Giving an absolute path instead (a name starting with `/`) overrides
that default and installs at the literal path given -- useful when something else expects the
secret at a specific, fixed location. Reference the resolved path either way via `path`,
mirroring `config.sops.secrets."<name>".path`:

```nix
systemd.services.newt.serviceConfig.LoadCredential =
  "client-secret:${config.secret.files."newt/clientSecret".path}";
```

> [!NOTE]
> `secret.files."<name>"` (plural, this install function) installs a decrypted file/directory.
> `secret.ref."<key>"` (singular, [an alias for `config.sops.placeholder`](#templated-files))
> references a decrypted value from inside `secret.templates` content. Easy to conflate by name --
> they're unrelated options.

##### Encrypted file
The file being consumed needs to have first been encrypted with sops. `key` defaults to the
attribute name, so naming the entry after the sops key (as below) needs no separate `key` field;
set `key` explicitly if you want a different sops key than the name/path used.

```nix
secret.files."newt/clientSecret".sopsFile = ./secrets.enc.yaml;   # -> /run/secrets/newt/clientSecret
```

##### Encrypted directory
Author the directory's content as one sops-encrypted yaml/json file, using genuine nesting
that mirrors the directory tree -- sops-install-secrets' `key` lookup treats `/` as a path
separator into nested maps, not a literal character in a flat key name:

```yaml
# certs.yaml, before `sops --encrypt`
nginx:
  certs:
    server.crt: |
      -----BEGIN CERTIFICATE-----
      ...
    server.key: |
      -----BEGIN PRIVATE KEY-----
      ...
```

```nix
secret.files."nginx/certs" = {
  sopsFile = ./certs.enc.yaml;
  prefix = "nginx/certs";   # setting prefix at all (even to "") selects directory-fanout mode
};   # -> /run/secrets/nginx/certs/<leaf>
```

#### Templated files
***secret.templates*** is its own standalone install function (like ***secret.users***, not a
field on `files.any`/`root`/`user`/`all`) for content rendered by sops-nix's template engine --
`content`/`file` may reference secret values via `config.secret.ref`. The attribute name is
just an identifier, mirroring sops-nix's own `sops.templates."<name>"` -- it's not the install
path. `path` sets the absolute destination and defaults to sops-nix's own
`/run/secrets/rendered/<name>` convention if left unset. `content`/`file` can't be merged into
one field the way `copy`/`weakCopy` accept either a string or a path: distinguishing which was
given requires checking the value's type (`builtins.isString`/`isPath`), and that check forces
the value -- which would recurse for `content`, since it may interpolate `config.sops.placeholder`
under the hood, itself only available once sops-nix already knows `sops.templates` is non-empty.
They're two separately-typed fields instead, and `file` takes precedence if both are set. Defaults
to `root:root` ownership and `0400` filemode, both overridable. Any `sops.secrets` a template's
placeholders need can be registered inline via its own `secrets` field instead of a separate
`sops.secrets.<key>` block:

```nix
secret.templates."cloudflare-env" = {
  path = "/run/caddy/cloudflare.env";
  user = "caddy"; group = "caddy";
  content = ''
    CF_ZONE=${config.secret.ref."caddy/cfZone"}
    CF_API_TOKEN=${config.secret.ref."caddy/cloudflareApiToken"}
  '';
  secrets = {
    "caddy/cfZone".sopsFile = ./secrets.enc.yaml;
    "caddy/cloudflareApiToken".sopsFile = ./secrets.enc.yaml;
  };
};
```

`config.secret.ref."<key>"` is a read-only alias for sops-nix's own
`config.sops.placeholder."<key>"` -- same value, same restriction (only meaningful inside
`secret.templates` `content`/`file`, since that's the only place sops-nix actually substitutes it
at activation time), just kept under the `secret.*` namespace instead of reaching into `sops.*`
directly. It works for any `config.sops.secrets` entry, however it was registered -- via a
template's own `secrets` field as above, via `secret.files`, or via plain `sops.secrets` -- not
just ones declared through `secret.templates`.

#### User created from a secret
When you want to create a user account without exposing to the world the name of your user you can
use the ***secret.users*** function which keeps the user and group names as placeholders to then
be set from secrets at activation time. This keeps them encrypted in your git repo and in the nix
store and only decrypted at activation time. This is of course idempotent and user accounts are only
ever created once.

Otherwise it behaves like a normal `users.users.<name>` entry -- `isNormalUser`, `uid`, and an
initial password (`passwordSecretRef`, mirroring `initialPassword`) all work the same way, and an
`isNormalUser` account gets the same default bash shell, `/home/<user>` home directory (mode
`0700`), and subuid/subgid range for rootless containers that a declarative one would. The
primary group always comes from `groupSecretRef` -- unlike `extraGroups`, its name is just as
sensitive as the username, so there's no plain `group` escape hatch. `extraGroups` is plain
supplementary membership in already-declared groups:

If you'd rather not have the plaintext password decrypted to disk at all, even transiently, use
`passwordHashSecretRef` instead of `passwordSecretRef` -- its secret should already be a hash
(e.g. `mkpasswd -m sha-512 'example-svc-password' 2>&1 || openssl passwd -6 'example-svc-password' 2>&1`), 
mirroring `users.users.<name>.hashedPassword`. The two are mutually exclusive on the same entry.

```nix
users.groups.shared = { };

secret.users."svc-account" = {
  sopsFile = ./secrets.enc.yaml;
  userSecretRef = "users/user1/name";
  groupSecretRef = "users/user1/group";
  passwordSecretRef = "users/user1/pass";
  isNormalUser = true;
  uid = 1500;
  extraGroups = [ "shared" ];
};
```

## Running the examples
See `examples/` for complete, evaluable configuration snippets. `examples/secrets.enc.yaml`
and `examples/certs.enc.yaml` are real sops-encrypted files, encrypted with the same disposable
test age key as `tests/fixtures/*.enc.yaml` (`tests/keys/test-age-key.txt`) purely so the
examples build end-to-end -- regenerate them with your own key for real usage.

Each file under `examples/` is also exposed as a `nixosConfigurations.example-<name>` flake
output (e.g. `plain-file.nix` -> `example-plain-file`), so you can build or boot any of them
directly without writing your own throwaway config:

### Build an example
Build an example and inspect the result
```bash
nix build .#nixosConfigurations.example-plain-file.config.system.build.toplevel
```

### Boot it in a VM
`examples/base.nix` bakes the disposable `tests/keys/test-age-key.txt` into the VM at
`/var/lib/sops-nix/key.txt` via `systemd.tmpfiles.rules`, so it boots straight into a working
example -- no manual key-copying step needed. Never do this with a real key.

1. Create and run the test VM:
   ```bash
   nixos-rebuild build-vm --flake .#example-user-from-secret
   ./result/bin/run-*-vm
   ```

2. Validate the existing encrypted user matches the one in the test vm
   ```bash
   SOPS_AGE_KEY_FILE=tests/keys/test-age-key.txt sops edit examples/secrets.enc.yaml
   ```

3. From inside the test VM retrigger activation
   ```bash
   /run/current-system/activate
   ```

### Build and eval-check
Build and eval-check every example at once
```bash
nix flake check
```

## Test suite

`tests/` is a NixOS VM test (`checks.<system>.vmTest`) that boots a machine wired up with every
engine at once -- plaintext `copy`/`link` across `files.any`/`root`/`user`/`all`, a single
sops-encrypted file, an encrypted directory fan-out, owner-from-secret resolution, a
`secret.templates` entry, and a user/group created from a secret -- then asserts the installed
content, mode, and owner at each target path. Unlike the `examples/`, which are only checked for evaluation, this
actually decrypts secrets and inspects the result, using the same disposable age keypair
(`tests/keys/test-age-key.txt`) that encrypts `examples/*.enc.yaml`, applied here to the
placeholder values in `tests/fixtures/*.enc.yaml`.

```bash
nix build .#checks.x86_64-linux.vmTest -L
```

`nix flake check` runs it alongside the example eval check.

## Backlog
* ?
