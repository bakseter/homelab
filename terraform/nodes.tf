locals {
  talos = {
    version = "v1.10.4"
  }

  k8s_virtual_nodes = {
    cp = {
      m720q = 1
      m715q = 2
    }

    worker = {
      m720q = 2
      m715q = 1
    }
  }

  k8s_physical_node_names = toset(
    flatten(
      [for node_type, nodes in local.k8s_virtual_nodes : keys(nodes) if length(nodes) > 0]
    )
  )

  k8s_virtual_node_names = toset(
    flatten(
      [for node_type, nodes in local.k8s_virtual_nodes :
        [for node_name, count in nodes :
          [for i in range(count) : "talos-${node_type}-${node_name}-${i + 1}"]
        ]
      ]
    )
  )

  k8s_cp_node_names = toset([
    for node_name in local.k8s_virtual_node_names :
    node_name if startswith(node_name, "talos-cp-")
  ])

  k8s_worker_node_names = toset([
    for node_name in local.k8s_virtual_node_names :
    node_name if startswith(node_name, "talos-worker-")
  ])

  static_ip_map = {
    "talos-cp-m720q-1"     = "192.168.1.50"
    "talos-worker-m720q-1" = "192.168.1.51"
    "talos-worker-m720q-2" = "192.168.1.52"

    "talos-cp-m715q-1"     = "192.168.1.60"
    "talos-cp-m715q-2"     = "192.168.1.61"
    "talos-worker-m715q-1" = "192.168.1.62"
  }

  all_nodes   = local.k8s_virtual_node_names
  ip_map_keys = keys(local.static_ip_map)
}

resource "proxmox_virtual_environment_download_file" "talos_nocloud_image" {
  for_each = local.k8s_physical_node_names

  content_type = "iso"
  datastore_id = "local"
  node_name    = each.value

  file_name               = "talos-${local.talos.version}-nocloud-amd64.img"
  url                     = "https://factory.talos.dev/image/787b79bb847a07ebb9ae37396d015617266b1cef861107eaec85968ad7b40618/${local.talos.version}/nocloud-amd64.raw.gz"
  decompression_algorithm = "gz"
  overwrite               = false
}

resource "proxmox_virtual_environment_vm" "talos_cp" {
  for_each = local.k8s_cp_node_names

  name        = each.key
  description = "Managed by Terraform"
  tags        = ["terraform"]
  node_name   = strcontains(each.key, "m720q") ? "m720q" : "m715q"
  on_boot     = true

  cpu {
    cores = 4
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  agent {
    enabled = true
  }

  network_device {
    bridge = "vmbr0"
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_virtual_environment_download_file.talos_nocloud_image[strcontains(each.key, "m720q") ? "m720q" : "m715q"].id
    file_format  = "raw"
    interface    = "virtio0"
    size         = strcontains(each.key, "m720q") ? 60 : 30
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "${local.static_ip_map[each.key]}/24"
        gateway = "192.168.1.1"
      }
    }
  }
}

resource "proxmox_virtual_environment_vm" "talos_worker" {
  for_each   = local.k8s_worker_node_names
  depends_on = [proxmox_virtual_environment_vm.talos_cp]

  name        = each.key
  description = "Managed by Terraform"
  tags        = ["terraform"]
  node_name   = strcontains(each.key, "m720q") ? "m720q" : "m715q"
  on_boot     = true

  cpu {
    cores = 4
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  agent {
    enabled = true
  }

  network_device {
    bridge = "vmbr0"
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_virtual_environment_download_file.talos_nocloud_image[strcontains(each.key, "m720q") ? "m720q" : "m715q"].id
    file_format  = "raw"
    interface    = "virtio0"
    size         = strcontains(each.key, "m720q") ? 60 : 30
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "${local.static_ip_map[each.key]}/24"
        gateway = "192.168.1.1"
      }
    }
  }
}
