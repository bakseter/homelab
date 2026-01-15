data "talos_image_factory_extensions_versions" "talos" {
  talos_version = local.talos_version
  filters = {
    names = [
      "siderolabs/iscsi-tools",
      "siderolabs/qemu-guest-agent",
      "siderolabs/util-linux-tools",
    ]
  }
}

resource "talos_image_factory_schematic" "talos" {
  schematic = yamlencode(
    {
      customization = {
        systemExtensions = {
          officialExtensions = data.talos_image_factory_extensions_versions.talos.extensions_info.*.name
        }
      }
    }
  )
}

resource "proxmox_virtual_environment_download_file" "talos-nocloud-image" {
  for_each = local.nodes

  content_type = "iso"
  datastore_id = "local"
  node_name    = each.key

  url       = "https://factory.talos.dev/image/${talos_image_factory_schematic.talos.id}/${local.talos_version}/nocloud-amd64.iso"
  overwrite = false
}

resource "proxmox_virtual_environment_vm" "talos-controlplane" {
  for_each = local.virtual_controlplane_nodes

  name          = each.key
  description   = "Managed by Terraform"
  tags          = ["terraform", "controlplane"]
  node_name     = each.value.parent_node
  on_boot       = true
  scsi_hardware = "virtio-scsi-single"

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory * 1024
  }

  agent {
    enabled = true
  }

  network_device {
    bridge = "vmbr0"
  }

  disk {
    datastore_id = "local-lvm"

    file_id     = proxmox_virtual_environment_download_file.talos-nocloud-image[each.value.parent_node].id
    file_format = "raw"

    interface = "scsi0"
    size      = each.value.disk

    cache    = "none"
    discard  = "on"
    iothread = true
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = "192.168.1.1"
      }
    }
  }
}

resource "proxmox_virtual_environment_vm" "talos-worker" {
  for_each   = local.virtual_worker_nodes
  depends_on = [proxmox_virtual_environment_vm.talos-controlplane]

  name          = each.key
  description   = "Managed by Terraform"
  tags          = ["terraform", "worker"]
  node_name     = each.value.parent_node
  on_boot       = true
  scsi_hardware = "virtio-scsi-single"

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory * 1024
  }

  agent {
    enabled = true
  }

  network_device {
    bridge = "vmbr0"
  }

  disk {
    datastore_id = "local-lvm"

    file_id     = proxmox_virtual_environment_download_file.talos-nocloud-image[each.value.parent_node].id
    file_format = "raw"

    interface = "scsi0"
    size      = each.value.disk

    cache    = "none"
    discard  = "on"
    iothread = true
  }

  dynamic "disk" {
    for_each = try(each.value.longhornDisk, null) != null ? [1] : []

    content {
      datastore_id = "local-lvm"

      interface = "scsi1"
      size      = each.value.longhornDisk

      cache    = "none"
      discard  = "on"
      iothread = true
    }
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = "192.168.1.1"
      }
    }
  }
}
