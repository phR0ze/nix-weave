# nixos-files

Activation-time NixOS file and secret installation, built on [sops-nix](https://github.com/Mic92/sops-nix).

Installs arbitrary files/directories -- plaintext or encrypted -- and renders templated files
mixing plaintext and secret fields, without ever writing decrypted secret content to the Nix
store or git. Encryption/templating are thin wrappers over sops-nix's own `sops.secrets`/
`sops.templates`, which decrypt only at activation time into `/run/secrets*`. Plaintext
copy/link installation is handled by a small ported activation script.

### Quick links
- [Overview](#overview)
  - [Install functions](#install-functions)
  - [File lifecycle ownership](#file-lifecycle-ownership)
  - [File ownership](#file-ownership)
  - [File permissions](#file-permissions)
- [Usage](#usage)
  - [Plaintext files](#plaintext-files)
    - [Install mechanisms](#install-mechanisms)
  - [Owner resolved from a secret](#owner-resolved-from-a-secret)
  - [Encrypted files](#encrypted-files)
    - [Encrypted file](#encrypted-file)
    - [Encrypted directory](#encrypted-directory)
  - [Templated file](#templated-file)
  - [User created from a secret](#user-created-from-a-secret)
- [Running the examples](#running-the-examples)
- [Test suite](#test-suite)
- [Backlog](#backlog)

## Overview

### Install functions
***nixos-files*** provides a number of different ***install functions*** for different purposes.
For every `files.<install-function>.<name>` the attribute IS the install path -- there's no separate
field to set. 

| Install function  | Description
| ----------------- | ---------------------------------------------------------------------
| `files.any`       | installs files at an arbitrary location on disk
| `files.root`      | installs files relative to `/root/`
| `files.user`      | installs files for all real users i.e. `isNormalUser = true`
| `files.all`       | installs files for both `/root/<name>` and `$HOME/<name>` for every real user
| `files.templates` | installs templated files at an arbitrary location on disk similar to `any`

### File lifecycle ownership
Ownership in this sense means who is responsible for the lifecycle of the files. If the files are
considered ***owned*** then nixos-files will manage the lifecycle and remove the file when no longer
specified in the configuration or overwrite on each activation with the specified content from the
configuration to ensure its always correct. If ***unowned*** then nixos-files will ensure the file is
installed if it doesn't exist and to not touch it after that.

The various content types below have a specific ownership type they evoke.
`copy`/`link`/`templates` are all **owned**. `weakCopy` is the only **unowned** case.

`copy`/`weakCopy`/`link` each accept either a string or a path -- a string is rendered to a Nix
store path first (not necessarily ASCII/text, and always a single file -- a directory tree
requires a path), a path (file, or whole directory for `link`) is used directly. Either way the
resulting content is installed the same way:

| Content types                            | Kind | Behavior 
| ---------------------------------------- | ---- | ------------------------------------------------------------------------------------------------
| `copy = ./src` or `copy = "..."`         | copy | Force-copies the content to the target on every activation, overwriting any local edits made since the last switch.
| `weakCopy = ./src` or `weakCopy = "..."` | copy | Copies the content to the target once, the first time it's installed, then leaves it (and any local edits to it) alone on every later activation.
| `link = ./src` or `link = "..."`         | link | Installs a readonly symlink at the target, pointed at the content via an atomic `/nix/files/<target>` indirection, so a source change swaps what's linked to in one atomic step.

`files.templates`' `content` is a separate case, always an inline string (never a path) -- see
[Templated file](#templated-file).

### File ownership
All files default to a particular user and group owner based on which install function was used, with
the option to then override in some cases.

* `files.any` - defaults to `root:root` and ***allows for overriding user and group***
* `files.root` - defaults to `root:root` and can not be overridden
* `files.user` - defaults to the implicated user and can not be overridden
* `files.all` - defaults to the implicated user and can not be overridden

The following provides examples of overridding the user and group for various cases.

```nix
files.templates."/run/caddy/cloudflare.env" = {
  user = "caddy"; group = "caddy"; filemode = "0400";
  content = ''
    CF_ZONE=example.com
    CF_API_TOKEN=${config.sops.placeholder."caddy/cloudflareApiToken"}
  '';
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
Import both `sops-nix.nixosModules.sops` and this flake's `nixosModules.default` -- nixos-files
never bundles or re-declares the sops-nix module itself, so you must import it yourself
alongside `nixos-files.nixosModules.default`. Pin `nixos-files`' and `sops-nix`'s own
`nixpkgs`/`sops-nix` inputs to `follows` your top-level ones -- without this, `nixpkgs` and
`sops-nix` each get resolved independently three times (top-level, sops-nix's own, and
nixos-files' own), which bloats the closure/eval time and risks nixos-files evaluating against
a different `lib`/sops-nix option schema than the one actually building your system:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    nixos-files.url = "github:phR0ze/nixos-files";
    nixos-files.inputs.nixpkgs.follows = "nixpkgs";
    nixos-files.inputs.sops-nix.follows = "sops-nix";
  };

  outputs = { nixpkgs, sops-nix, nixos-files, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        sops-nix.nixosModules.sops
        nixos-files.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

### Plaintext files
```nix
files.any."/etc/asound.conf".copy = "autospawn=no";
files.root.".dircolors".copy = ../include/home/.dircolors;                 # -> /root/.dircolors
files.user.".config/menus".link = ../include/xfce-menus;                   # -> every real user's $HOME/.config/menus
files.all.".motd".copy = "welcome\n";                                      # -> /root/.motd and every real user's $HOME/.motd
```

### Owner resolved from a secret
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

### Encrypted files
nixos-files provides the ability to encrypt 1 or more files or directories.

#### Encrypted file
```nix
files.any."/etc/newt/client-secret" = {
  encrypted = { sopsFile = ./secrets.enc.yaml; key = "newt/clientSecret"; };
  filemode = "0400";
};
```

#### Encrypted directory
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
files.any."/etc/nginx/certs" = {
  encryptedDir = { sopsFile = ./certs.enc.yaml; prefix = "nginx/certs"; };
  filemode = "0400";
};
```

### Templated file
Templates live in their own `files.templates` namespace, separate from `files.any`/`root`/
`user`/`all` -- content may reference `config.sops.placeholder`, and keeping templates out of
the auto-detecting `files.*` submodule avoids a NixOS module-system evaluation cycle (checking
whether another engine's field is set would otherwise force this string, including its
placeholder interpolation, before `sops.placeholder` itself is available). The attribute name IS
the install path and must already be absolute, including the leading `/`, same as `files.any`
(evaluation fails otherwise):

```nix
files.templates."/run/caddy/cloudflare.env" = {
  user = "caddy"; group = "caddy"; filemode = "0400";
  content = ''
    CF_ZONE=example.com
    CF_API_TOKEN=${config.sops.placeholder."caddy/cloudflareApiToken"}
  '';
};
```

### User created from a secret

For the rare case where even the account/group name itself is sensitive: `users.fromSecret`
creates a system user and group at activation time, decrypted from sops secrets rather than
declared via ordinary `users.users`/`users.groups` -- which can't express this, since NixOS's
declarative user/group activation rewrites `/etc/passwd`/`/etc/group` from attribute names fixed
at Nix eval time, before any secret is decrypted. `<name>` is just an internal identifier here
(like `sops.secrets.<name>`), not the real account name. Create-once: re-running activation never
touches an account that already exists.

```nix
users.fromSecret."svc-account" = {
  sopsFile = ./secrets.enc.yaml;
  userSecretRef = "provisioned/svcUsername";
  groupSecretRef = "provisioned/svcGroupname";
};
```

See `examples/` for complete, evaluable configuration snippets. `examples/secrets.enc.yaml`
and `examples/certs.enc.yaml` are real sops-encrypted files, encrypted with the same disposable
test age key as `tests/fixtures/*.enc.yaml` (`tests/keys/test-age-key.txt`) purely so the
examples build end-to-end -- regenerate them with your own key for real usage.

## Running the examples

Each file under `examples/` is also exposed as a `nixosConfigurations.example-<name>` flake
output (e.g. `plain-file.nix` -> `example-plain-file`), so you can build or boot any of them
directly without writing your own throwaway config:

### Build an example
Build an example and inspect the result
```bash
nix build .#nixosConfigurations.example-plain-file.config.system.build.toplevel
```

### Boot it in a VM
Boot it in a VM and see the real activation script run

```bash
nixos-rebuild build-vm --flake .#example-plain-file
./result/bin/run-*-vm
```

### Build and eval-check
Build and eval-check every example at once
```bash
nix flake check
```

## Test suite

`tests/` is a NixOS VM test (`checks.<system>.vmTest`) that boots a machine wired up with every
engine at once -- plaintext `copy`/`link` across `files.any`/`root`/`user`/`all`, a single
sops-encrypted file, an encrypted directory fan-out, owner-from-secret resolution, a templated
file, and a user/group created from a secret -- then asserts the installed content, mode, and
owner at each target path. Unlike the `examples/`, which are only checked for evaluation, this
actually decrypts secrets and inspects the result, using the same disposable age keypair
(`tests/keys/test-age-key.txt`) that encrypts `examples/*.enc.yaml`, applied here to the
placeholder values in `tests/fixtures/*.enc.yaml`.

```bash
nix build .#checks.x86_64-linux.vmTest -L
```

`nix flake check` runs it alongside the example eval check.

## Backlog
* ?
