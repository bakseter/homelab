locals {
  cluster_name = "homelab"

  # Separate IP lists for CP and workers (to use for client config endpoints)
  talos_cp_ip_addresses = {
    for k, v in local.static_ip_map : k => v if startswith(k, "talos-cp-")
  }

  talos_worker_ip_addresses = {
    for k, v in local.static_ip_map : k => v if startswith(k, "talos-worker-")
  }
}

resource "talos_machine_secrets" "machine_secrets" {}

data "talos_client_configuration" "talosconfig" {
  cluster_name         = local.cluster_name
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration

  # Pass all CP IPs as endpoints (you can add worker IPs if needed)
  endpoints = values(local.talos_cp_ip_addresses)
}

data "talos_machine_configuration" "machineconfig_cp" {
  for_each = toset(keys(local.talos_cp_ip_addresses))

  cluster_name     = local.cluster_name
  cluster_endpoint = "https://${local.talos_cp_ip_addresses[each.key]}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
}

resource "talos_machine_configuration_apply" "cp_config_apply" {
  for_each   = toset(keys(local.talos_cp_ip_addresses))
  depends_on = [proxmox_virtual_environment_vm.talos_cp]

  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_cp[each.key].machine_configuration
  node                        = local.talos_cp_ip_addresses[each.key]

  config_patches = each.key == "talos-cp-m715q-1" ? [
    yamlencode({
      machine = {
        kubelet = {
          extraArgs = {
            rotate-server-certificates = true
          }
        }
      },
      cluster = {
        extraManifests = [
          "https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml",
          "https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml",
        ]
      }
    })
    ] : [
    yamlencode({
      machine = {
        kubelet = {
          extraArgs = {
            rotate-server-certificates = true
          }
        }
      }
    })
  ]
}

data "talos_machine_configuration" "machineconfig_worker" {
  for_each = toset(keys(local.talos_worker_ip_addresses))

  cluster_name     = local.cluster_name
  cluster_endpoint = "https://${local.talos_cp_ip_addresses["talos-cp-m720q-1"]}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
}

resource "talos_machine_configuration_apply" "worker_config_apply" {
  for_each   = toset(keys(local.talos_worker_ip_addresses))
  depends_on = [proxmox_virtual_environment_vm.talos_worker]

  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_worker[each.key].machine_configuration
  node                        = local.talos_worker_ip_addresses[each.key]
  config_patches = [
    yamlencode({
      machine = {
        kubelet = {
          extraArgs = {
            rotate-server-certificates = true
          }
        }
      }
    })
  ]
}

resource "talos_machine_bootstrap" "bootstrap" {
  depends_on = [talos_machine_configuration_apply.cp_config_apply]

  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = local.talos_cp_ip_addresses["talos-cp-m720q-1"]
}

resource "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on = [talos_machine_bootstrap.bootstrap]

  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = local.talos_cp_ip_addresses["talos-cp-m720q-1"]
}

output "talosconfig" {
  value     = data.talos_client_configuration.talosconfig.talos_config
  sensitive = true
}

output "kubeconfig" {
  value     = talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
  sensitive = true
}
