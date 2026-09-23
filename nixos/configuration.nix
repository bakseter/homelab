{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot = {
    loader.systemd-boot.enable = true;
    loader.systemd-boot.configurationLimit = 10;
    loader.efi.canTouchEfiVariables = true;
    kernelPackages = pkgs.linuxPackages_latest;
    kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
  };

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  networking = {
    hostName = "infra";
    interfaces.eno1.useDHCP = true;
    firewall = {
      enable = true;
      checkReversePath = "loose"; # required for Tailscale
    };
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
    extraSetFlags = [
      "--advertise-exit-node"
      "--advertise-routes=192.168.10.0/24,192.168.20.0/24,192.168.30.0/24,192.168.70.0/24"
      "--accept-dns=false"
      "--relay-server-port=40000"
    ];
  };

  time.timeZone = "Europe/Amsterdam";

  users.groups.infra-secrets = { };

  users.users.ops = {
    isNormalUser = true;
    extraGroups = [ "wheel" "infra-secrets" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILj87yRsywKKxceR6a42/JTomwQvvQvEcyjIkxillZYw andreas_tkd@hotmail.com" # deskarch
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHr1nJQfTlfcbCyZQK6/hc/3A6lKI+4cE+kshlhqf3tA andreas_tkd@hotmail.com" # archpad
    ];
  };

  programs.ssh.startAgent = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  environment.systemPackages = with pkgs; [
    (python3.withPackages (ps: with ps; [ librouteros ansible-core ]))
    arp-scan
    cilium-cli
    curl
    ethtool
    fastfetch
    git
    htop
    hubble
    jq
    kubectl
    kubernetes-helm
    lshw
    net-tools
    opentofu
    sshpass
    talosctl
    vim
    wget
    yq-go
  ];

  # Break-glass: `tofu-env`, then tofu works. Alias expansion runs in the
  # current shell, so this really does export into your session.
  environment.shellAliases.tofu-env =
    "set -a; . ${config.sops.templates."tofu.env".path}; set +a";

  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    # The host's age identity is derived from its SSH host key. Nothing extra
    # to back up: if the box boots, it can decrypt.
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    age.generateKey = false;

    secrets."ssh/mikrotik-key" = {
      mode = "0440";
      group = "infra-secrets";
    };

    # One rendered env file, shared by the runner (EnvironmentFile) and you
    # (the alias above). Credentials reach tasks through the process
    # environment, so they never enter Semaphore's database.
    #
    # One file covers both tofu roots: OpenTofu silently ignores TF_VAR_*
    # env vars for variables a root doesn't declare, so `core` is unbothered
    # by the apps variables and vice versa.
    #
    # HCL ignores whitespace, which is why TF_ENCRYPTION fits on one line --
    # systemd EnvironmentFile has no multi-line syntax.
    templates."tofu.env" = {
      mode = "0440";
      group = "infra-secrets";
      content = ''
        AWS_ACCESS_KEY_ID=${config.sops.placeholder."hetzner/access-key"}
        AWS_SECRET_ACCESS_KEY=${config.sops.placeholder."hetzner/secret-key"}
        TF_ENCRYPTION=key_provider "pbkdf2" "main" { passphrase = "${config.sops.placeholder."tofu/passphrase"}" } method "aes_gcm" "main" { keys = key_provider.pbkdf2.main } state { method = method.aes_gcm.main } plan { method = method.aes_gcm.main }

        # tofu/core
        TF_VAR_proxmox_username=${config.sops.placeholder."core/proxmox-username"}
        TF_VAR_proxmox_password=${config.sops.placeholder."core/proxmox-password"}

        # tofu/apps
        TF_VAR_tailscale_oauth_client_id=${config.sops.placeholder."apps/tailscale-oauth-client-id"}
        TF_VAR_tailscale_oauth_client_secret=${config.sops.placeholder."apps/tailscale-oauth-client-secret"}
        TF_VAR_cloudflare_api_token=${config.sops.placeholder."apps/cloudflare-api-token"}
        TF_VAR_cloudflare_account_id=${config.sops.placeholder."apps/cloudflare-account-id"}
        TF_VAR_authentik_url=${config.sops.placeholder."apps/authentik-url"}
        TF_VAR_authentik_token=${config.sops.placeholder."apps/authentik-token"}
      '';
    };
  };

  users.groups.semaphore-runner = { };
  users.users.semaphore-runner = {
    isSystemUser = true;
    group = "semaphore-runner";
    extraGroups = [ "infra-secrets" ];
  };

  systemd.services.semaphore-runner = {
    description = "Semaphore UI remote runner";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "tailscaled.service" ];
    wants = [ "network-online.target" ];

    # Tasks are child processes, so they inherit this. Reusing the system
    # package list means there's one place to add a tool, not two.
    path = config.environment.systemPackages;

    environment = {
      HOME = "/var/lib/semaphore-runner";
      TF_IN_AUTOMATION = "1";
      TF_INPUT = "0";
    };

    serviceConfig = {
      User = "semaphore-runner";
      Group = "semaphore-runner";
      StateDirectory = "semaphore-runner";
      WorkingDirectory = "/var/lib/semaphore-runner";
      EnvironmentFile = config.sops.templates."tofu.env".path;
      ExecStart =
        "${pkgs.semaphore}/bin/semaphore runner start"
        + " --config /var/lib/semaphore-runner/config.json";
      Restart = "always";
      RestartSec = "10s";
      ProtectHome = true;
    };
  };

  system.stateVersion = "25.11"; # do not change
}
