# nixos-files

Activation-time NixOS file and secret installation, built on [sops-nix](https://github.com/Mic92/sops-nix).

Installs arbitrary files/directories -- plaintext or encrypted -- and renders templated files
mixing plaintext and secret fields, without ever writing decrypted secret content to the Nix
store or git. Encryption/templating are thin wrappers over sops-nix's own `sops.secrets`/
`sops.templates`, which decrypt only at activation time into `/run/secrets*`. Plaintext
copy/link installation is handled by a small ported activation script.

### Quick links
* [Usage](#usage)
  * [Namespaces](#namespaces)
  * [Plaintext files](#plaintext-files)
  * [Encrypted file](#encrypted-file)
  * [Encrypted directory](#encrypted-directory)
  * [Templated file](#templated-file)
  * [Owner resolved from a secret](#owner-resolved-from-a-secret)
* [Running the examples](#running-the-examples)
* [Test suite](#test-suite)
* [Backlog](#backlog)

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

`files.user`/`files.all` need no configuration of their own -- they install for every real user
already declared via ordinary NixOS `users.users.<name> = { isNormalUser = true; ... };`
entries. nixos-files has no notion of a single "primary" user; it just looks at
`config.users.users`.

### Namespaces

- `files.any.<name>` -- installed at an arbitrary absolute path, owned root:root by default
- `files.root.<name>` -- installed under `/root/`, owned root:root
- `files.user.<name>` -- installed under every real user's home directory (every
  `config.users.users` entry with `isNormalUser = true`), owned by that user
- `files.all.<name>` -- installed both for root (`/root/<name>`) and for every real user

For `files.any`/`files.root`, `target` is an absolute path. For `files.user`/`files.all`,
`target` is instead relative to each user's home directory (e.g. `.config/menus`, not
`/home/alice/.config/menus`) -- it gets expanded into one instance per real user at activation
time, so it can't be pinned to a single absolute path.

### Plaintext files

```nix
files.root.".dircolors".copy = ../include/home/.dircolors;
files.user.".config/menus".link = ../include/xfce-menus;   # -> every real user's $HOME/.config/menus
files.any."etc/asound.conf".text = "autospawn=no";
```

`copy` force-overwrites on every switch; `weakCopy` copies once and never again; `link`
installs a readonly symlink via an atomic `/nix/files` indirection.

### Encrypted file

```nix
files.root."newt-secret" = {
  target = "/etc/newt/client-secret";
  encrypted = { sopsFile = ./secrets.enc.yaml; key = "newt/clientSecret"; };
  filemode = "0400";
};
```

### Encrypted directory

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
files.root."nginx-certs" = {
  target = "/etc/nginx/certs";
  encryptedDir = { sopsFile = ./certs.enc.yaml; prefix = "nginx/certs"; };
  filemode = "0400";
};
```

### Templated file

Templates live in their own `files.templates` namespace, separate from `files.any`/`root`/
`user`/`all` -- content may reference `config.sops.placeholder`, and keeping templates out of
the auto-detecting `files.*` submodule avoids a NixOS module-system evaluation cycle (checking
whether another engine's field is set would otherwise force this string, including its
placeholder interpolation, before `sops.placeholder` itself is available):

```nix
files.templates."caddy-env" = {
  target = "/run/caddy/cloudflare.env";
  user = "caddy"; group = "caddy"; filemode = "0400";
  content = ''
    CF_ZONE=example.com
    CF_API_TOKEN=${config.sops.placeholder."caddy/cloudflareApiToken"}
  '';
};
```

### Owner resolved from a secret

For the rare case where even the account name is sensitive (plaintext engine only):

```nix
files.root."svc-file" = {
  target = "/opt/svc/data";
  copy   = ../include/svc/data;
  user   = { secretRef = "provisioned/svcUser"; sopsFile = ./secrets.enc.yaml; };
};
```

See `examples/` for complete, evaluable configuration snippets. `examples/secrets.enc.yaml`
and `examples/certs.enc.yaml` are real sops-encrypted files, encrypted with a disposable demo
age key (not used anywhere else) purely so the examples build end-to-end -- regenerate them
with your own key for real usage.

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
engine at once -- plaintext `text`/`copy`/`link` across `files.any`/`root`/`user`/`all`, a single
sops-encrypted file, an encrypted directory fan-out, owner-from-secret resolution, and a
templated file -- then asserts the installed content, mode, and owner at each target path. Unlike
the `examples/`, which are only checked for evaluation, this actually decrypts secrets and
inspects the result, using a disposable age keypair (`tests/keys/test-age-key.txt`) that only
ever encrypts the placeholder values in `tests/fixtures/*.enc.yaml`.

```bash
nix build .#checks.x86_64-linux.vmTest -L
```

`nix flake check` runs it alongside the example eval check.

## Backlog
* ?
