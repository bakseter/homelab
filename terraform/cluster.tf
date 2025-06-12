locals {
  cluster_name = "homelab"
}

resource "talos_machine_secrets" "machine_secrets" {}

data "talos_client_configuration" "talosconfig" {
  cluster_name         = local.cluster_name
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  endpoints            = values(local.talos_cp_ip_addresses)
}

data "talos_machine_configuration" "machineconfig_cp" {
  for_each = local.k8s_cp_node_names

  cluster_name     = local.cluster_name
  cluster_endpoint = "https://${local.talos_cp_ip_addresses[each.key]}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
}

resource "talos_machine_configuration_apply" "cp_config_apply" {
  for_each   = local.k8s_cp_node_names
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
        },
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
        },
      },
    })
  ]
}

data "talos_machine_configuration" "machineconfig_worker" {
  for_each = local.k8s_worker_node_names

  cluster_name     = local.cluster_name
  cluster_endpoint = "https://${local.talos_worker_ip_addresses[each.key]}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
}

resource "talos_machine_configuration_apply" "worker_config_apply" {
  for_each   = local.k8s_worker_node_names
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
        },
      },
    })
  ]
}

resource "talos_machine_bootstrap" "bootstrap" {
  depends_on = [talos_machine_configuration_apply.cp_config_apply]

  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = values(local.talos_cp_ip_addresses)[0]
}

#data "talos_cluster_health" "health" {
#  depends_on           = [talos_machine_configuration_apply.cp_config_apply, talos_machine_configuration_apply.worker_config_apply]
#
#  client_configuration = data.talos_client_configuration.talosconfig.client_configuration
#  control_plane_nodes  = [local.talos_cp_01_ip_addr]
#  worker_nodes         = [local.talos_worker_01_ip_addr]
#  endpoints            = data.talos_client_configuration.talosconfig.endpoints
#}

resource "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on = [talos_machine_bootstrap.bootstrap]

  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = values(local.talos_cp_ip_addresses)[0]
}

output "talosconfig" {
  value     = data.talos_client_configuration.talosconfig.talos_config
  sensitive = true
}

output "kubeconfig" {
  value     = talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
  sensitive = true
}
