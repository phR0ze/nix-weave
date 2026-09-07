{
  description = "Activation-time NixOS file/secret installation, built on sops-nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, sops-nix, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];

      exampleNames = [
        "plain-file"
        "plain-directory"
        "encrypted-file"
        "encrypted-directory"
        "templated-file"
        "owner-from-secret"
        "user-from-secret"
        "user-from-password-hash"
      ];

      mkExample = system: name: nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.default
          ./examples/base.nix
          (./examples + "/${name}.nix")
        ];
      };
    in {
      # Bundles sops-nix's own module alongside nixos-files' -- consumers only need to import
      # this one output. If a consumer also imports sops-nix.nixosModules.sops directly
      # themselves (e.g. for their own unrelated sops.secrets), NixOS dedupes identical-path
      # module imports automatically, but only if both resolve to the exact same sops-nix input
      # -- pin `nixos-files.inputs.sops-nix.follows = "sops-nix";` in the consumer's own flake if
      # they need that guarantee (see README).
      nixosModules.default = {
        imports = [
          sops-nix.nixosModules.sops
          (import ./modules)
        ];
      };

      # Small reusable helpers (yaml/json reading, id derivation) usable by downstream
      # projects building their own convenience wrappers on top of the fileType submodule.
      lib = import ./modules/lib.nix { inherit (nixpkgs) lib; pkgs = null; };

      # `nix build .#nixosConfigurations.example-<name>.config.system.build.toplevel`, or
      # `nixos-rebuild build-vm --flake .#example-<name>` to boot one and inspect it live.
      nixosConfigurations = nixpkgs.lib.genAttrs
        (map (name: "example-${name}") exampleNames)
        (attrName: mkExample "x86_64-linux" (nixpkgs.lib.removePrefix "example-" attrName));

      # `nix build .#checks.<system>.vmTest -L`, or `nix flake check`, to boot a VM and assert
      # every engine (plaintext copy/link, sops-nix encrypted file/directory, owner-from-secret,
      # files.templates, user-from-secret) actually installs correctly at activation time.
      checks = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; }; in
        {
          eval = (mkExample system "plain-file").config.system.build.toplevel;

          vmTest = import ./tests {
            inherit pkgs;
            nixos-files = self.nixosModules.default;
          };
        });
    };
}
