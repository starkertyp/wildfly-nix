{ pkgs }:

let
  war = pkgs.runCommand "test.war" { nativeBuildInputs = [ pkgs.zip ]; } ''
    mkdir -p d/WEB-INF
    echo "wildfly-ok" > d/index.html
    (cd d && zip -r $out .)
  '';

  # The deployment name determines the WildFly context path.
  context = "/test/";
in
pkgs.testers.nixosTest {
  name = "wildfly";

  nodes.machine = {
    imports = [ ../modules/wildfly.nix ];

    environment.systemPackages = [ pkgs.curl ];

    services.wildfly = {
      enable = true;
      deployments = [ { name = "test"; path = war; } ];
      jdbcDrivers = [ pkgs.postgresql_jdbc ];
    };

    virtualisation.memorySize = 2048;
  };

  testScript = ''
    machine.wait_for_unit("wildfly.service")
    machine.wait_for_open_port(8080)
    machine.wait_until_succeeds("curl --fail -s http://127.0.0.1:8080${context} | grep -q wildfly-ok", timeout=300)

    # The driver jar is symlinked into the deployments dir and WildFly registers it as a driver deployment.
    machine.succeed("test -L /var/lib/wildfly/deployments/postgresql-jdbc.jar")
    machine.wait_until_succeeds(
      "grep -qi 'Started Driver service with driver-name = .*postgresql-jdbc.jar' /var/lib/wildfly/log/server.log",
      timeout=300,
    )
  '';
}
