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
      ];

      mkExample = system: name: nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          sops-nix.nixosModules.sops
          self.nixosModules.default
          ./examples/base.nix
          (./examples + "/${name}.nix")
        ];
      };
    in {
      nixosModules.default = import ./modules;

      # Small reusable helpers (yaml/json reading, id derivation) usable by downstream
      # projects building their own convenience wrappers on top of the fileType submodule.
      lib = import ./modules/lib.nix { inherit (nixpkgs) lib; pkgs = null; };

      # `nix build .#nixosConfigurations.example-<name>.config.system.build.toplevel`, or
      # `nixos-rebuild build-vm --flake .#example-<name>` to boot one and inspect it live.
      nixosConfigurations = nixpkgs.lib.genAttrs
        (map (name: "example-${name}") exampleNames)
        (attrName: mkExample "x86_64-linux" (nixpkgs.lib.removePrefix "example-" attrName));

      # `nix build .#checks.<system>.vmTest -L`, or `nix flake check`, to boot a VM and assert
      # every engine (plaintext copy/link/text, sops-nix encrypted file/directory,
      # owner-from-secret, templated content) actually installs correctly at activation time.
      checks = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; }; in
        {
          eval = (mkExample system "plain-file").config.system.build.toplevel;

          vmTest = import ./tests {
            inherit pkgs sops-nix;
            nixos-files = self.nixosModules.default;
          };
        });
    };
}
