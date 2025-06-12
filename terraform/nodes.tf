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
      m715q = 0
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
    dedicated = strcontains(each.key, "m720q") ? 4096 : 2048 # m715q has less RAM
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
    size         = strcontains(each.key, "m720q") ? 60 : 30 # m715q has less disk space
  }

  operating_system {
    type = "l26" # Linux Kernel 2.6 - 5.X.
  }

  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "dhcp"
      }

      ipv6 {
        address = "dhcp"
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
    dedicated = strcontains(each.key, "m720q") ? 4096 : 2048 # m715q has less RAM
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
    size         = strcontains(each.key, "m720q") ? 60 : 30 # m715q has less disk space
  }

  operating_system {
    type = "l26" # Linux Kernel 2.6 - 5.X.
  }

  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "dhcp"
      }

      ipv6 {
        address = "dhcp"
      }
    }
  }
}

locals {
  talos_cp_ip_addresses     = { for vm in proxmox_virtual_environment_vm.talos_cp : vm.name => vm.ipv4_addresses[7][0] }
  talos_worker_ip_addresses = { for vm in proxmox_virtual_environment_vm.talos_worker : vm.name => vm.ipv4_addresses[7][0] }
}
