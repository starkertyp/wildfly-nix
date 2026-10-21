# WildFly on NixOS

NixOS module and package for WildFly 41.0.1.Final on JDK 21. WildFly is started
inside an FHS environment (`buildFHSEnv`), because its distribution scripts and
modules expect standard FHS paths.

## Usage

```nix
{
  inputs.wildfly-nix-setup.url = "github:you/wildfly-nix-setup";

  outputs = { nixpkgs, wildfly-nix-setup, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      modules = [
        wildfly-nix-setup.nixosModules.default
        ({ pkgs, ... }: {
          services.wildfly.enable = true;
          services.wildfly.deployments = [
            # context path /myapp
            { name = "myapp"; path = ./myapp.war; }
            # context path derived from the file name
            ./other.war
          ];
          # JDBC drivers from nixpkgs, see "JDBC drivers" below
          services.wildfly.jdbcDrivers = [ pkgs.postgresql_jdbc ];
        })
      ];
    };
  };
}
```

NOTE: This uses stable nixpkgs (currently `26.05`) as people who want to run wildfly will likely value stability.
Override `inputs.wildfly.inputs.nixpkgs` to change this.

## Options

| Option | Default | Description |
| --- | --- | --- |
| `services.wildfly.enable` | `false` | Enable the service |
| `services.wildfly.package` | WildFly package from this flake | WildFly package |
| `services.wildfly.user` / `group` | `"wildfly"` | Service user and group |
| `services.wildfly.stateDir` | `"/var/lib/wildfly"` | State directory |
| `services.wildfly.config` | `"standalone.xml"` | Configuration file name |
| `services.wildfly.bindAddress` | `"0.0.0.0"` | Public bind address |
| `services.wildfly.managementBindAddress` | `"127.0.0.1"` | Management bind address |
| `services.wildfly.httpPort` / `httpsPort` | `8080` / `8443` | HTTP(S) ports |
| `services.wildfly.managementPort` | `9990` | Management HTTP port |
| `services.wildfly.deployments` | `[]` | WAR files, or `{ name, path; }` sets |
| `services.wildfly.jdbcDrivers` | `[]` | JDBC driver packages whose `share/java/*.jar` are deployed |
| `services.wildfly.extraJavaOptions` | `[]` | Additional JVM options |
| `services.wildfly.openFirewall` | `false` | Open HTTP/HTTPS ports |

## State directory

`/var/lib/wildfly` contains:

- `configuration/` – seeded from the package on first start only. Later changes
  to the packaged `standalone.xml` are not propagated; edit the file in the
  state directory and restart the service.
- `deployments/` – managed by the service; WAR files and JDBC driver jars are
  symlinked from the Nix store and the directory is wiped for
  `.war`/`.dodeploy`/`.jar` files on every start.
- `data/`, `tmp/`, `log/` – runtime data.

Deployments are symlinked into `deployments/`. A deployment given as a bare path
is linked under its store file name (including the hash), so prefer
`{ name = "myapp"; path = ...; }` to get a stable context path `/myapp`.

Changing the package or the deployment list restarts the service.

## JDBC drivers

Drivers come from nixpkgs packages (`services.wildfly.jdbcDrivers`), pinned by
the flake lock, so no jar has to be downloaded by hand. Their
`share/java/*.jar` files are linked into `deployments/` and registered
automatically, each under the jar file name (e.g. `postgresql-jdbc.jar`).

Only the driver is made discoverable. The datasource itself is still configured
by hand in `configuration/standalone.xml` or with `jboss-cli`, where the driver
is then selectable by that name.

## License

The packaging code in this repository (flake, module, tests, package definition) is
licensed under the EUPL-1.2 (see [LICENSE](LICENSE)).

WildFly itself is shipped unmodified as the upstream release and is licensed under
the Apache License 2.0 (see `LICENSE.txt` in the WildFly release); bundled
third-party modules keep their own licences.
