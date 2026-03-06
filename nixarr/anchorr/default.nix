{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.anchorr;
  globals = config.util-nixarr.globals;
  nixarr = config.nixarr;
  port = 8282;
in {
  options.nixarr.anchorr = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Anchorr service.
      '';
    };

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./package.nix {};
      defaultText = literalExpression "pkgs.callPackage ./package.nix {}";
      description = "The package used for the Anchorr service.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/anchorr";
      defaultText = literalExpression ''"''${nixarr.stateDir}/anchorr"'';
      example = "/nixarr/.state/anchorr";
      description = ''
        The location of the state directory for the Anchorr service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/anchorr
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    port = mkOption {
      type = types.port;
      default = port;
      example = 12345;
      description = "Anchorr web-UI port.";
    };

    openFirewall = mkOption {
      type = types.bool;
      defaultText = literalExpression ''!nixarr.anchorr.vpn.enable'';
      default = !cfg.vpn.enable;
      example = true;
      description = "Open firewall for Anchorr";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        **Conflicting options:** [`nixarr.anchorr.expose.https.enable`](#nixarr.anchorr.expose.https.enable)

        Route Anchorr traffic through the VPN.
      '';
    };

    expose = {
      https = {
        enable = mkOption {
          type = types.bool;
          default = false;
          example = true;
          description = ''
            **Required options:**

            - [`nixarr.anchorr.expose.https.acmeMail`](#nixarr.anchorr.expose.https.acmemail)
            - [`nixarr.anchorr.expose.https.domainName`](#nixarr.anchorr.expose.https.domainname)

            **Conflicting options:** [`nixarr.anchorr.vpn.enable`](#nixarr.anchorr.vpn.enable)

            Expose the Anchorr web service to the internet with https support,
            allowing anyone to access it.

            > **Warning:** Do _not_ enable this without setting up Anchorr
            > authentication through localhost first!
          '';
        };

        upnp.enable = mkEnableOption "UPNP to try to open ports 80 and 443 on your router.";

        domainName = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "anchorr.example.com";
          description = "The domain name to host Anchorr on.";
        };

        acmeMail = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "mail@example.com";
          description = "The ACME mail required for the letsencrypt bot.";
        };
      };
    };
  };

  config = mkIf (nixarr.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> nixarr.vpn.enable;
        message = ''
          The nixarr.anchorr.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
      {
        assertion = !(cfg.vpn.enable && cfg.expose.https.enable);
        message = ''
          The nixarr.anchorr.vpn.enable option conflicts with the
          nixarr.anchorr.expose.https.enable option. You cannot set both.
        '';
      }
      {
        assertion =
          cfg.expose.https.enable
          -> (
            (cfg.expose.https.domainName != null)
            && (cfg.expose.https.acmeMail != null)
          );
        message = ''
          The nixarr.anchorr.expose.https.enable option requires the
          following options to be set, but one of them were not:

          - nixarr.anchorr.expose.https.domainName
          - nixarr.anchorr.expose.https.acmeMail
        '';
      }
    ];

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0700 ${globals.anchorr.user} root - -"
    ];

    systemd.services.anchorr = {
      description = "Anchorr, a Discord bot for media requests";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      environment = {
        WEBHOOK_PORT = toString cfg.port;
      };

      serviceConfig = {
        Type = "exec";
        StateDirectory = "anchorr";
        WorkingDirectory = cfg.stateDir;
        DynamicUser = false;
        User = globals.anchorr.user;
        Group = globals.anchorr.group;
        ExecStart = lib.getExe cfg.package;
        Restart = "on-failure";

        # Security
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectHostname = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        NoNewPrivileges = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
        PrivateMounts = true;
        ProtectSystem = "strict";
        ReadWritePaths = [cfg.stateDir];
      };
    };

    users = {
      groups.${globals.anchorr.group}.gid = globals.gids.${globals.anchorr.group};
      users.${globals.anchorr.user} = {
        isSystemUser = true;
        group = globals.anchorr.group;
        uid = globals.uids.${globals.anchorr.user};
      };
    };

    networking.firewall = mkMerge [
      (mkIf cfg.expose.https.enable {
        allowedTCPPorts = [80 443];
      })
      (mkIf cfg.openFirewall {
        allowedTCPPorts = [cfg.port];
      })
    ];

    util-nixarr.upnp = mkIf cfg.expose.https.upnp.enable {
      enable = true;
      openTcpPorts = [80 443];
    };

    services.nginx = mkMerge [
      (mkIf (cfg.expose.https.enable || cfg.vpn.enable) {
        enable = true;

        recommendedTlsSettings = true;
        recommendedOptimisation = true;
        recommendedGzipSettings = true;
      })
      (mkIf cfg.expose.https.enable {
        virtualHosts."${builtins.replaceStrings ["
"] [""] cfg.expose.https.domainName}" = {
          enableACME = true;
          forceSSL = true;
          locations."/" = {
            recommendedProxySettings = true;
            proxyWebsockets = true;
            proxyPass = "http://127.0.0.1:${builtins.toString cfg.port}";
          };
        };
      })
      (mkIf cfg.vpn.enable {
        virtualHosts."127.0.0.1:${builtins.toString cfg.port}" = {
          listen = [
            {
              addr = "0.0.0.0";
              port = cfg.port;
            }
          ];
          locations."/" = {
            recommendedProxySettings = true;
            proxyWebsockets = true;
            proxyPass = "http://192.168.15.1:${builtins.toString cfg.port}";
          };
        };
      })
    ];

    security.acme = mkIf cfg.expose.https.enable {
      acceptTerms = true;
      defaults.email = cfg.expose.https.acmeMail;
    };

    # Enable and specify VPN namespace to confine service in.
    systemd.services.anchorr.vpnConfinement = mkIf cfg.vpn.enable {
      enable = true;
      vpnNamespace = "wg";
    };

    # Port mappings
    vpnNamespaces.wg = mkIf cfg.vpn.enable {
      portMappings = [
        {
          from = cfg.port;
          to = cfg.port;
        }
      ];
    };
  };
}
