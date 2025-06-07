{
  description = "Pulse – an Odin + raylib game, packaged with Nix flake";

  inputs = {
    nixpkgs.url    = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        runtimeLibs = with pkgs; [
          raylib
          glfw
          libGL            
          xorg.libX11
          xorg.libXrandr
          xorg.libXcursor
          xorg.libXi
          freetype
          fontconfig
          expat
          libxkbcommon
          wayland
        ];

        buildInputs = runtimeLibs ++ (with pkgs; [
          odin
          clang
          pkg-config
        ]);

        libPath = pkgs.lib.makeLibraryPath runtimeLibs;
      in {

        packages.default = pkgs.stdenv.mkDerivation {
          pname = "pulse";
          version = "0.1.0";

          src = ./.;
          nativeBuildInputs = buildInputs;
          buildInputs        = buildInputs;

          buildPhase = ''
            odin build src -debug -out:pulse
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp pulse $out/bin/
            wrapProgram $out/bin/pulse \
              --prefix LD_LIBRARY_PATH : ${libPath}
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = buildInputs;
          LD_LIBRARY_PATH = libPath;
        };
      });
}

