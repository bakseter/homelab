locals {
  cluster_name = "homelab"
}

resource "talos_machine_secrets" "machine_secrets" {}

data "talos_client_configuration" "talosconfig" {
  cluster_name         = local.cluster_name
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  endpoints            = [local.talos_cp_01_ip_addr]
}

data "talos_machine_configuration" "machineconfig_cp" {
  cluster_name     = local.cluster_name
  cluster_endpoint = "https://${local.talos_cp_01_ip_addr}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
}

resource "talos_machine_configuration_apply" "cp_config_apply" {
  depends_on                  = [proxmox_virtual_environment_vm.talos_cp_01]
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_cp.machine_configuration
  count                       = 1
  node                        = local.talos_cp_01_ip_addr
  config_patches = [
    yamlencode({
      machine = {
        kubelet = {
          extraArgs = {
            rotate-server-certificates = true
          }
        },
        nodeLabels = {
          "node.kubernetes.io/exclude-from-external-load-balancers" = ""
          "$patch"                                                  = "delete"
        }
      }
    })
  ]
}

data "talos_machine_configuration" "machineconfig_worker" {
  cluster_name     = local.cluster_name
  cluster_endpoint = "https://${local.talos_cp_01_ip_addr}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
}

resource "talos_machine_configuration_apply" "worker_config_apply" {
  depends_on                  = [proxmox_virtual_environment_vm.talos_worker_01]
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_worker.machine_configuration
  count                       = 1
  node                        = local.talos_worker_01_ip_addr
  config_patches = [
    yamlencode({
      machine = {
        kubelet = {
          extraArgs = {
            rotate-server-certificates = true
          }
        },
      }
    })
  ]
}

resource "talos_machine_bootstrap" "bootstrap" {
  depends_on           = [talos_machine_configuration_apply.cp_config_apply]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = local.talos_cp_01_ip_addr
}

/*
data "talos_cluster_health" "health" {
  depends_on           = [talos_machine_configuration_apply.cp_config_apply, talos_machine_configuration_apply.worker_config_apply]
  client_configuration = data.talos_client_configuration.talosconfig.client_configuration
  control_plane_nodes  = [local.talos_cp_01_ip_addr]
  worker_nodes         = [local.talos_worker_01_ip_addr]
  endpoints            = data.talos_client_configuration.talosconfig.endpoints
}
*/

resource "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on           = [talos_machine_bootstrap.bootstrap]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = local.talos_cp_01_ip_addr
}

output "talosconfig" {
  value     = data.talos_client_configuration.talosconfig.talos_config
  sensitive = true
}

output "kubeconfig" {
  value     = talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
  sensitive = true
}
