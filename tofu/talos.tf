resource "talos_machine_secrets" "machine_secrets" {
  talos_version = local.talos_version
}

data "talos_client_configuration" "talosconfig" {
  cluster_name         = local.cluster_name
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration

  # Pass all CP IPs as endpoints (you can add worker IPs if needed)
  endpoints = [for node_name, node in local.virtual_controlplane_nodes : node.ip]
}

data "talos_machine_configuration" "machineconfig_controlplane" {
  for_each = local.virtual_controlplane_nodes

  cluster_name     = local.cluster_name
  cluster_endpoint = "https://${each.value.ip}:6443"
  machine_type     = each.value.type
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
}

resource "talos_machine_configuration_apply" "controlplane_config_apply" {
  for_each   = local.virtual_controlplane_nodes
  depends_on = [proxmox_virtual_environment_vm.talos-controlplane]

  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_controlplane[each.key].machine_configuration
  node                        = each.value.ip

  config_patches = compact([
    templatefile(
      "${path.module}/manifests/default-patches.yaml.tmpl",
      {
        physical_node_name      = split("-", each.key)[0]
        hostname                = each.value.hostname
        node_ip                 = each.value.ip
        node_type               = each.value.type
        virtual_ip_controlplane = local.virtual_ip_controlplane
        talos_schematic_id      = talos_image_factory_schematic.talos.id
        talos_version           = local.talos_version
      }
    )
  ])
}

data "talos_machine_configuration" "machineconfig_worker" {
  for_each = local.virtual_worker_nodes

  talos_version    = local.talos_version
  cluster_name     = local.cluster_name
  cluster_endpoint = "https://${local.main_virtual_controlplane_node}:6443"
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.machine_secrets.machine_secrets
}

resource "talos_machine_configuration_apply" "worker_config_apply" {
  for_each   = local.virtual_worker_nodes
  depends_on = [proxmox_virtual_environment_vm.talos-worker]

  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_worker[each.key].machine_configuration
  node                        = each.value.ip

  config_patches = compact([
    try(each.value.longhorn.enabled, false) ? templatefile(
      "${path.module}/manifests/longhorn-patches.yaml.tmpl",
      {
        extension_image_refs = data.talos_image_factory_extensions_versions.talos.extensions_info.*.ref
      },
    ) : "",
    try(each.value.igpu.enabled, false) ? file(
      "${path.module}/manifests/igpu-patches.yaml",
    ) : "",
    templatefile(
      "${path.module}/manifests/default-patches.yaml.tmpl",
      {
        physical_node_name      = split("-", each.key)[0]
        hostname                = each.value.hostname
        node_ip                 = each.value.ip
        node_type               = each.value.type
        virtual_ip_controlplane = local.virtual_ip_controlplane
        talos_schematic_id      = talos_image_factory_schematic.talos.id
        talos_version           = local.talos_version
      }
    )
  ])
}

resource "talos_machine_bootstrap" "bootstrap" {
  depends_on = [talos_machine_configuration_apply.controlplane_config_apply]

  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = local.main_virtual_controlplane_node
}

resource "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on = [talos_machine_bootstrap.bootstrap]

  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = local.main_virtual_controlplane_node
}

output "talosconfig" {
  value     = data.talos_client_configuration.talosconfig.talos_config
  sensitive = true
}

output "kubeconfig" {
  value     = talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
  sensitive = true
}
