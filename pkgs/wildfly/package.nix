{ lib
, stdenv
, fetchurl
, buildFHSEnv
, jdk21
, writeShellScript
}:

let
  version = "42.0.0.Final";

  # Distribution scripts keep their #!/bin/sh shebangs; they only run inside the FHS env.
  unwrapped = stdenv.mkDerivation {
    pname = "wildfly";
    inherit version;

    src = fetchurl {
      url = "https://github.com/wildfly/wildfly/releases/download/${version}/wildfly-${version}.tar.gz";
      hash = "sha256-bC5QuPPiwMOtj1JB4YJ28Sv9Pm43t1Dj/h1s4d0oAM4=";
    };

    dontPatchShebangs = true;

    installPhase = ''
      mkdir -p $out
      cp -r ./* $out/
    '';
  };
in
buildFHSEnv {
  name = "wildfly";

  targetPkgs = pkgs: [
    pkgs.jdk21
    pkgs.bash
    pkgs.coreutils
    pkgs.gnused
    pkgs.gnugrep
    pkgs.findutils
    pkgs.which
    pkgs.procps
  ];

  runScript = writeShellScript "wildfly-start" ''
    export JAVA_HOME=${jdk21}
    exec ${unwrapped}/bin/standalone.sh "$@"
  '';

  meta = {
    description = "WildFly application server";
    homepage = "https://www.wildfly.org/";
    # Upstream WildFly is Apache-2.0; bundled third-party modules keep their own licences.
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    # Upstream release tarball is a binary distribution, not source.
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
  };

  passthru.unwrapped = unwrapped;
}
