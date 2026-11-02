{ lib
, stdenv
, fetchurl
, maven
, jdk21
, jre-generate-cacerts
, buildFHSEnv
, writeShellScript
}:

let
  version = "42.0.0.Final";

  src = fetchurl {
    url = "https://codeload.github.com/wildfly/wildfly/tar.gz/refs/tags/${version}";
    name = "wildfly-${version}-src.tar.gz";
    hash = "sha256-ePUchOnxQo9wFbbOhQE6bEWR5d/5SlLBMkPh/KvKSMs=";
  };

  mvnArgs = "-B -nsu -DskipTests -Denforcer.skip=true -Dcheckstyle.skip=true";

  # WildFly's Galleon feature packs read the poms of artifacts built in the same
  # reactor from the local Maven repository, so the build has to `install`.
  mavenDeps = stdenv.mkDerivation {
    pname = "wildfly-${version}-maven-deps";
    inherit version src;

    # jre-generate-cacerts must not be in nativeBuildInputs: stdenv then runs it
    # during setup, where it fails. It is only referenced by path below.
    nativeBuildInputs = [ maven ];
    env.JAVA_HOME = jdk21;

    buildPhase = ''
      runHook preBuild
      mvnExtraArgs=""
      if [ -e "''${NIX_SSL_CERT_FILE:-/nonexistent}" ]; then
        ${jre-generate-cacerts} ${lib.getBin jdk21}/bin/keytool "$NIX_SSL_CERT_FILE"
        mvnExtraArgs="-Djavax.net.ssl.trustStore=cacerts -Djavax.net.ssl.trustStorePassword=changeit"
      fi
      mvn ${mvnArgs} $mvnExtraArgs -Dmaven.repo.local="$out/.m2" install
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      # Keep only downloaded artifacts in the pinned repository. Artifacts installed
      # from the reactor are rebuilt for every output and would make the hash unstable.
      find "$out/.m2" -name 'maven-metadata-local.xml' -delete
      find "$out/.m2" -name '_remote.repositories' -print0 | while IFS= read -r -d "" marker; do
        if grep -q '>=$' "$marker"; then
          rm -rf "$(dirname "$marker")"
        fi
      done
      find "$out" -type f \
        \( -name '*.lastUpdated' -o -name resolver-status.properties -o -name '_remote.repositories' \) \
        -delete

      runHook postInstall
    '';

    dontFixup = true;
    outputHashMode = "recursive";
    outputHash = "sha256-T6ycb8W8/k7hfY8HofTyOHqZ1uTR9LnTzKu+9NHosac=";
  };

  unwrapped = stdenv.mkDerivation {
    pname = "wildfly";
    inherit version src;

    nativeBuildInputs = [ maven ];
    env.JAVA_HOME = jdk21;

    dontPatchShebangs = true;

    buildPhase = ''
      runHook preBuild
      mvnDeps=$(cp -dpR ${mavenDeps}/.m2 ./ && chmod -R u+w .m2 && pwd)
      mvn ${mvnArgs} -o "-Dmaven.repo.local=$mvnDeps/.m2" install
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      # Galleon copies the jars built in this reactor. A mismatch would mean it
      # used prebuilt artifacts from the dependency repository instead.
      cmp dist/target/wildfly-${version}/modules/system/layers/base/org/wildfly/extension/undertow/main/wildfly-undertow-${version}.jar \
          undertow/target/wildfly-undertow-${version}.jar

      mkdir -p $out
      cp -a dist/target/wildfly-${version}/. $out/

      runHook postInstall
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
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };

  passthru.unwrapped = unwrapped;
}
