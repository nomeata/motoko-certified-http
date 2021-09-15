{ rev    ? "4c2e7becf1c942553dadd6527996d25dbf5a7136"
, sha256 ? "10dzi5xizgm9b3p5k963h5mmp0045nkcsabqyarpr7mj151f6jpm"
, pkgs   ? import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/${rev}.tar.gz";
    inherit sha256; }) {
    config.allowUnfree = true;
    config.allowBroken = false;
  }
}:

rec {

dfx = pkgs.stdenv.mkDerivation rec {
  pname = "dfx";
  version = "0.8.1";

  src = fetchTarball {
    url = "https://sdk.dfinity.org/downloads/dfx/${version}/x86_64-linux/dfx-${version}.tar.gz";
    sha256 = "1ifc7n9kl4rzvhfs9xbbaj9wsnhw0wzlnyjswcgl38mljvkxxvw2";
  };

  nativeBuildInputs = [
    pkgs.autoPatchelfHook
    pkgs.makeWrapper
  ];

  phases = [ "unpackPhase" "installPhase" "fixupPhase" ];

  # dfx contains other binaries that need to be patched for nixos and that are
  # extracted at runtime. So let’s make dfx extract them now, and then wrap
  # it to use these files
  installPhase = ''
    mkdir -p $out/bin
    cp -v dfx $out/bin/

    # does not work well, DFX_CONFIG_ROOT changes too much

    # export DFX_CONFIG_ROOT=$out
    # export DFX_TELEMETRY_DISABLED=1
    # autoPatchelfFile $out/bin/dfx
    # $out/bin/dfx cache show
    # $out/bin/dfx cache install
    # wrapProgram $out/bin/dfx --set DFX_CONFIG_ROOT $out --set DFX_TELEMETRY_DISABLED 1
  '';
};

vessel = pkgs.stdenv.mkDerivation rec {
  pname = "vessel";
  version = "0.6.2";

  bin = pkgs.fetchurl {
    url = "https://github.com/dfinity/vessel/releases/download/v${version}/vessel-linux64";
    sha256 = "1d0djh2m2m86zrbpwkpr80mfxccr2glxf6kq15hpgx48m74lsmsp";
  };

  buildInputs = [ pkgs.openssl ];

  nativeBuildInputs = [
    pkgs.autoPatchelfHook
  ];

  phases = [ "installPhase" "fixupPhase" ];

  installPhase = ''
    mkdir -p $out/bin
    cp -v $bin $out/bin/vessel
    chmod +x $out/bin/vessel
  '';
};

moc =
  let
  src = fetchTarball {
    url = "https://github.com/dfinity/motoko/archive/refs/tags/0.6.8.tar.gz";
    sha256 = "17a444wdzmgmwpgh0mbc8x4g40mqk996f1rf2ypjficzvrb2mj1a";
  };
  in (import src {}).moc;

shell = pkgs.mkShell {
  buildInputs = [ dfx moc vessel ];
};

}
