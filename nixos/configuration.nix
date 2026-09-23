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

  # systemd-resolved is what makes accept-dns safe. Without it, Tailscale
  # rewrites /etc/resolv.conf wholesale and every lookup goes to MagicDNS --
  # which is presumably why --accept-dns=false was set in the first place.
  # With resolved, Tailscale registers 100.100.100.100 as a *routing-only*
  # resolver for its own domains and leaves everything else on your LAN
  # resolver. That's the split you want on a box that is also the subnet
  # router for four VLANs.
  services.resolved.enable = true;

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
    extraSetFlags = [
      "--advertise-exit-node"
      "--advertise-routes=192.168.10.0/24,192.168.20.0/24,192.168.30.0/24,192.168.70.0/24"
      "--accept-dns=true"
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

  # Nix evaluates the flake with libgit2, which refuses a repo owned by
  # someone other than the calling user. nixos-rebuild runs as root, the repo
  # lives in ops's home, so root needs to be told it's fine.
  programs.git = {
    enable = true;
    config.safe.directory = [ "/home/ops/homelab" ];
  };

  environment.systemPackages = with pkgs; [
    (python3.withPackages (ps: with ps; [ librouteros ansible-core ]))
    arp-scan
    cilium-cli
    curl
    ethtool
    fastfetch
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

    # Every key referenced by a template below must be declared here --
    # sops.placeholder only resolves for declared secrets. Defaults (0400,
    # root) are fine: only root renders the templates. The consequence is that
    # each value lands on disk twice, once at /run/secrets/<name> and once
    # inside the rendered env file. sops-nix has no way around that.
    secrets = {
      "hetzner/access-key" = { };
      "hetzner/secret-key" = { };
      "tofu/passphrase" = { };

      "core/proxmox-username" = { };
      "core/proxmox-password" = { };

      "apps/tailscale-oauth-client-id" = { };
      "apps/tailscale-oauth-client-secret" = { };
      "apps/cloudflare-api-token" = { };
      "apps/cloudflare-account-id" = { };
      "apps/authentik-url" = { };
      "apps/authentik-token" = { };

      "semaphore/registration-token" = { };
    };

    # One rendered env file, read two ways: systemd hands it to the container
    # as an EnvironmentFile, and the `tofu-env` alias sources it into your
    # shell. Credentials reach tasks through the process environment, so they
    # never enter Semaphore's database.
    #
    # EVERY VALUE IS SINGLE-QUOTED, and it has to be. systemd tolerates bare
    # spaces in an EnvironmentFile value; bash does not -- `VAR=a b c` runs
    # `b c` as a command. Both parsers strip the outer single quotes. This
    # breaks if a value ever contains a single quote; base64 and hex never do.
    #
    # TF_ENCRYPTION carries ONE HCL block, nothing more. HCL wants a newline
    # after every block definition, and neither parser here carries newlines
    # inside a value -- so the method/state/plan blocks live in each root's
    # backend.tf instead, and OpenTofu merges the two.
    #
    # One file covers both tofu roots: OpenTofu silently ignores TF_VAR_*
    # env vars for variables a root doesn't declare, so `core` is unbothered
    # by the apps variables and vice versa.
    templates."tofu.env" = {
      mode = "0440";
      group = "infra-secrets";
      content = ''
        AWS_ACCESS_KEY_ID='${config.sops.placeholder."hetzner/access-key"}'
        AWS_SECRET_ACCESS_KEY='${config.sops.placeholder."hetzner/secret-key"}'
        TF_ENCRYPTION='key_provider "pbkdf2" "main" { passphrase = "${config.sops.placeholder."tofu/passphrase"}" }'

        # tofu/core
        TF_VAR_proxmox_username='${config.sops.placeholder."core/proxmox-username"}'
        TF_VAR_proxmox_password='${config.sops.placeholder."core/proxmox-password"}'

        # tofu/apps
        TF_VAR_tailscale_oauth_client_id='${config.sops.placeholder."apps/tailscale-oauth-client-id"}'
        TF_VAR_tailscale_oauth_client_secret='${config.sops.placeholder."apps/tailscale-oauth-client-secret"}'
        TF_VAR_cloudflare_api_token='${config.sops.placeholder."apps/cloudflare-api-token"}'
        TF_VAR_cloudflare_account_id='${config.sops.placeholder."apps/cloudflare-account-id"}'
        TF_VAR_authentik_url='${config.sops.placeholder."apps/authentik-url"}'
        TF_VAR_authentik_token='${config.sops.placeholder."apps/authentik-token"}'
      '';
    };

    # Separate from tofu.env because that one is also sourced into your shell
    # by the `tofu-env` alias, and Semaphore's token has no business there.
    templates."semaphore.env" = {
      mode = "0400";
      content = ''
        SEMAPHORE_RUNNER_REGISTRATION_TOKEN='${config.sops.placeholder."semaphore/registration-token"}'
      '';
    };
  };

  # Semaphore isn't in nixpkgs, so the runner comes from upstream's image.
  # oci-containers is the declarative-container layer: the unit below is a
  # normal systemd service, generated from this, and nothing is stored outside
  # git except the runner's own auth token.
  #
  # backend defaults to podman (no daemon, NixOS default). Set it to "docker"
  # if you'd rather -- the container config is identical either way.
  virtualisation.oci-containers = {
    backend = "podman";
    containers.semaphore-runner = {
      image = "semaphoreui/runner:v2.19.14";

      # Host networking: the runner has to reach the VLANs, the Talos API and
      # your cluster ingress. This is the whole reason it lives on this box.
      extraOptions = [ "--network=host" ];

      environment = {
        # Verify these names against `semaphore runner setup` for your image
        # tag -- SEMAPHORE_RUNNER_* naming has shifted across 2.1x releases.
        SEMAPHORE_WEB_ROOT = "https://semaphore.int.bakseter.net";
        SEMAPHORE_RUNNER_CONFIG_FILE = "/var/lib/semaphore/runner.config";
        TF_IN_AUTOMATION = "1";
        TF_INPUT = "0";

        # Nix toolchain first, image's own tooling behind it. Only meaningful
        # with the /nix/store mount below; drop this line if you skip it.
        PATH = "${pkgs.lib.makeBinPath config.environment.systemPackages}"
          + ":/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
      };

      environmentFiles = [
        config.sops.templates."tofu.env".path
        config.sops.templates."semaphore.env".path
      ];

      volumes = [
        "/var/lib/semaphore-runner:/var/lib/semaphore"

        # OPTIONAL, but this is what buys back what the container costs you.
        # The image ships its own tofu and ansible, and has no librouteros for
        # the community.routeros API modules. Mounting the store and putting a
        # nix-built toolchain first on PATH restores both, still flake-pinned.
        # Drop this pair of lines if your MikroTik playbooks only use the
        # SSH-based modules and you're happy with the image's tofu version.
        "/nix/store:/nix/store:ro"
      ];
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/semaphore-runner 0700 root root -"
  ];

  system.stateVersion = "25.11"; # do not change
}
