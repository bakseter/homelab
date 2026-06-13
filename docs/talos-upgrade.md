# Upgrading Talos

```bash
export TALOS_VERSION=1.13.4

# Controlplane nodes, one at a time.
#
# Extensions: none

talosctl -n 192.168.30.100 upgrade --image factory.talos.dev/nocloud-installer/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba:v${TALOS_VERSION}
talosctl -n 192.168.30.110 upgrade --image factory.talos.dev/nocloud-installer/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba:v${TALOS_VERSION}
talosctl -n 192.168.30.120 upgrade --image factory.talos.dev/nocloud-installer/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba:v${TALOS_VERSION}

# Intel worker nodes, one at a time.
#
# Extensions:
# - i915
# - intel-ucode
# - iscsi-tools
# - qemu-guest-agent
# - util-linux-tools

talosctl -n 192.168.30.101 upgrade --image factory.talos.dev/nocloud-installer/eed1860a28ccc6fdb77f1f41ab0ae2a20c19bc6101618d416d5d72ec919bf679:v${TALOS_VERSION}
talosctl -n 192.168.30.131 upgrade --image factory.talos.dev/nocloud-installer/eed1860a28ccc6fdb77f1f41ab0ae2a20c19bc6101618d416d5d72ec919bf679:v${TALOS_VERSION}

# AMD worker noces, one at a time.
#
# Extensions:
# - iscsi-tools
# - qemu-guest-agent
# - util-linux-tools

talosctl -n 192.168.30.111 upgrade --image factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v${TALOS_VERSION}
talosctl -n 192.168.30.121 upgrade --image factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v${TALOS_VERSION}
```
