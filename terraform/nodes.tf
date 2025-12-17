resource "proxmox_virtual_environment_download_file" "talos_nocloud_image" {
  for_each = local.nodes

  content_type = "iso"
  datastore_id = "local"
  node_name    = each.key

  url       = "https://factory.talos.dev/image/077514df2c1b6436460bc60faabc976687b16193b8a1290fda4366c69024fec2/v1.11.6/nocloud-amd64.iso"
  overwrite = false
}

resource "proxmox_virtual_environment_vm" "talos_controlplane" {
  for_each = local.virtual_controlplane_nodes

  name          = each.key
  description   = "Managed by Terraform"
  tags          = ["terraform"]
  node_name     = each.value.parent_node
  on_boot       = true
  scsi_hardware = "virtio-scsi-single"

  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
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

    file_id     = proxmox_virtual_environment_download_file.talos_nocloud_image[each.value.parent_node].id
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

resource "proxmox_virtual_environment_vm" "talos_worker" {
  for_each   = local.virtual_worker_nodes
  depends_on = [proxmox_virtual_environment_vm.talos_controlplane]

  name          = each.key
  description   = "Managed by Terraform"
  tags          = ["terraform"]
  node_name     = each.value.parent_node
  on_boot       = true
  scsi_hardware = "virtio-scsi-single"

  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
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

    file_id     = proxmox_virtual_environment_download_file.talos_nocloud_image[each.value.parent_node].id
    file_format = "raw"

    interface = "scsi0"
    size      = each.value.disk

    cache    = "none"
    discard  = "on"
    iothread = true
  }

  disk {
    datastore_id = "local-lvm"

    interface = "scsi1"
    size      = each.value.longhornDisk

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
