{ config, lib, pkgs, ... }:

let
  cfg = config.services.wildfly;

  deploymentPath = deployment:
    if builtins.isAttrs deployment then deployment.path else deployment;

  # WildFly derives the context path from the deployment file name.
  deploymentLinkName = deployment:
    let name = if builtins.isAttrs deployment then deployment.name else baseNameOf (toString deployment);
    in if lib.hasSuffix ".war" name then name else "${name}.war";

  prepare = pkgs.writeShellScript "wildfly-prepare" ''
    set -eu

    state=${lib.escapeShellArg cfg.stateDir}
    mkdir -p "$state"/{configuration,deployments,data,tmp,log}

    # shortcut: the configuration is seeded only on first start, upgrades have to be applied manually.
    if [ ! -e "$state/configuration/${cfg.config}" ]; then
      cp -f ${cfg.package.unwrapped}/standalone/configuration/* "$state/configuration/"
      chmod -R u+w "$state/configuration"
    fi

    deploy="$state/deployments"
    rm -f "$deploy"/*.war "$deploy"/*.dodeploy "$deploy"/*.jar
    ${lib.concatMapStringsSep "\n" (deployment:
      let
        path = lib.escapeShellArg (toString (deploymentPath deployment));
        link = lib.escapeShellArg (deploymentLinkName deployment);
      in ''
        case ${path} in
          *.war) ln -sfn ${path} "$deploy"/${link} ;;
          *) echo "services.wildfly.deployments: ${toString (deploymentPath deployment)} is not a .war" >&2; exit 1 ;;
        esac
      '') cfg.deployments}
    ${lib.concatMapStringsSep "\n" (driver: ''
      for jar in ${lib.escapeShellArg (toString driver)}/share/java/*.jar; do
        if [ ! -e "$jar" ]; then
          echo "services.wildfly.jdbcDrivers: ${toString driver} has no share/java/*.jar" >&2
          exit 1
        fi
        ln -sfn "$jar" "$deploy"/
      done
    '') cfg.jdbcDrivers}
  '';
in
{
  options.services.wildfly = {
    enable = lib.mkEnableOption "WildFly application server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../pkgs/wildfly/package.nix { };
      description = "WildFly package to use.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "wildfly";
      description = "User account under which WildFly runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "wildfly";
      description = "Group under which WildFly runs.";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/wildfly";
      description = "Directory holding configuration, deployments and runtime data.";
    };

    config = lib.mkOption {
      type = lib.types.str;
      default = "standalone.xml";
      description = "Standalone configuration file used on startup.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Public interface address.";
    };

    managementBindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Management interface address.";
    };

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "HTTP port.";
    };

    httpsPort = lib.mkOption {
      type = lib.types.port;
      default = 8443;
      description = "HTTPS port.";
    };

    managementPort = lib.mkOption {
      type = lib.types.port;
      default = 9990;
      description = "Management HTTP port.";
    };

    deployments = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.path (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Deployment file name without .war, which becomes the context path.";
          };
          path = lib.mkOption {
            type = lib.types.path;
            description = "WAR file to deploy.";
          };
        };
      }));
      default = [ ];
      description = ''
        WAR files to deploy, either as a path (file name becomes the context path)
        or as an attribute set with `name` and `path`.
      '';
    };

    jdbcDrivers = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = ''
        JDBC driver packages (e.g. pkgs.postgresql_jdbc) whose `$out/share/java/*.jar`
        are symlinked into the managed deployments dir, so WildFly auto-detects them
        as JDBC drivers.
      '';
    };

    extraJavaOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra JVM options passed to WildFly.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open HTTP and HTTPS ports in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.stateDir;
    };

    users.groups.${cfg.group} = { };

    systemd.services.wildfly = {
      description = "WildFly application server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      restartTriggers = [ cfg.package ] ++ map deploymentPath cfg.deployments ++ cfg.jdbcDrivers;

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.stateDir;
        Restart = "on-failure";
        ExecStartPre = prepare;
        ExecStart = lib.escapeShellArgs ([
          "${cfg.package}/bin/wildfly"
          "-c" cfg.config
          "-Djboss.server.base.dir=${cfg.stateDir}"
          "-Djboss.bind.address=${cfg.bindAddress}"
          "-Djboss.bind.address.management=${cfg.managementBindAddress}"
          "-Djboss.http.port=${toString cfg.httpPort}"
          "-Djboss.https.port=${toString cfg.httpsPort}"
          "-Djboss.management.http.port=${toString cfg.managementPort}"
        ] ++ cfg.extraJavaOptions);
      } // lib.optionalAttrs (lib.hasPrefix "/var/lib/" cfg.stateDir) {
        StateDirectory = lib.removePrefix "/var/lib/" cfg.stateDir;
      } // lib.optionalAttrs (!lib.hasPrefix "/var/lib/" cfg.stateDir) {
        ReadWritePaths = [ cfg.stateDir ];
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      cfg.httpPort
      cfg.httpsPort
    ];
  };
}
