data "talos_image_factory_extensions_versions" "initial-talos" {
  talos_version = local.initial_talos_version

  filters = {
    names = [
      "siderolabs/iscsi-tools",
      "siderolabs/qemu-guest-agent",
      "siderolabs/util-linux-tools",
    ]
  }
}

resource "talos_image_factory_schematic" "initial-talos" {
  schematic = yamlencode(
    {
      customization = {
        systemExtensions = {
          officialExtensions = data.talos_image_factory_extensions_versions.initial-talos.extensions_info.*.name
        }
      }
    }
  )
}

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

resource "proxmox_download_file" "talos-nocloud-image" {
  for_each = local.nodes

  content_type = "iso"
  datastore_id = "local"
  node_name    = each.key

  url       = "https://factory.talos.dev/image/${talos_image_factory_schematic.talos.id}/${local.initial_talos_version}/nocloud-amd64.iso"
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
    enabled = false
  }

  network_device {
    bridge  = "vmbr0"
    vlan_id = 30
  }

  disk {
    datastore_id = "local-lvm"

    file_id     = proxmox_download_file.talos-nocloud-image[each.value.parent_node].id
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
    bridge  = "vmbr0"
    vlan_id = 30
  }

  disk {
    datastore_id = "local-lvm"

    file_id     = proxmox_download_file.talos-nocloud-image[each.value.parent_node].id
    file_format = "raw"

    interface = "scsi0"
    size      = each.value.disk

    cache    = "none"
    discard  = "on"
    iothread = true
  }

  dynamic "disk" {
    for_each = try(each.value.longhorn.enabled, null) != null ? [1] : []

    content {
      datastore_id      = ""
      path_in_datastore = each.value.longhorn.pathInDatastore

      interface   = "scsi1"
      size        = each.value.longhorn.diskSize
      file_format = "raw"

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

resource "proxmox_virtual_environment_cluster_firewall" "datacenter" {
  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"

  log_ratelimit {
    enabled = true
    burst   = 5
    rate    = "1/second"
  }
}

resource "proxmox_node_firewall" "node" {
  for_each = local.nodes
  depends_on = [
    proxmox_virtual_environment_cluster_firewall.datacenter,
    proxmox_virtual_environment_vm.talos-controlplane,
    proxmox_virtual_environment_vm.talos-worker,
  ]

  node_name     = each.key
  enabled       = true
  log_level_in  = "warning"
  log_level_out = "warning"
}

resource "proxmox_virtual_environment_firewall_ipset" "management" {
  name    = "management"
  comment = "Admin workstations and management VLAN"

  cidr { name = "192.168.10.0/24" }
  cidr { name = "192.168.40.0/24" } # desktop VLAN
}

resource "proxmox_virtual_environment_firewall_ipset" "cluster_nodes" {
  name    = "cluster-nodes"
  comment = "All Proxmox nodes and Talos VMs"

  # TODO: use config.yaml for this
  # Physical nodes
  cidr { name = "192.168.10.20" }
  cidr { name = "192.168.10.21" }
  cidr { name = "192.168.10.22" }
  cidr { name = "192.168.10.33" }

  # TODO: use config.yaml for this
  # Controlplane VMs
  cidr { name = "192.168.30.100" }
  cidr { name = "192.168.30.110" }
  cidr { name = "192.168.30.120" }
  cidr { name = "192.168.30.190" }


  # TODO: use config.yaml for this
  # Worker VMs
  cidr { name = "192.168.30.101" }
  cidr { name = "192.168.30.111" }
  cidr { name = "192.168.30.121" }
  cidr { name = "192.168.30.131" }
}

resource "proxmox_virtual_environment_firewall_rules" "node" {
  for_each   = local.nodes
  depends_on = [proxmox_node_firewall.node]

  node_name = each.key

  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = "+management"
    dport   = "22"
    proto   = "tcp"
    comment = "SSH from management"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = "+management"
    dport   = "8006"
    proto   = "tcp"
    comment = "Proxmox UI"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = "+cluster-nodes"
    dport   = "5405:5412"
    proto   = "udp"
    comment = "Corosync"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = "+cluster-nodes"
    dport   = "60000:60050"
    proto   = "tcp"
    comment = "Live migration"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = "+cluster-nodes"
    dport   = "8472"
    proto   = "udp"
    comment = "Cilium VXLAN"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = "+cluster-nodes"
    dport   = "4240"
    proto   = "tcp"
    comment = "Cilium healthcheck"
  }
}

resource "proxmox_virtual_environment_firewall_rules" "talos-controlplane" {
  for_each   = local.virtual_controlplane_nodes
  depends_on = [proxmox_virtual_environment_vm.talos-controlplane]

  node_name = each.key
  vm_id     = proxmox_virtual_environment_vm.talos-controlplane[each.key].vm_id

  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = "+cluster-nodes"
    dport   = "6443"
    proto   = "tcp"
    comment = "k8s API"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = "+cluster-nodes"
    dport   = "50000"
    proto   = "tcp"
    comment = "Talos API"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = "+cluster-nodes"
    dport   = "2379:2380"
    proto   = "tcp"
    comment = "etcd"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = "+cluster-nodes"
    dport   = "8472"
    proto   = "udp"
    comment = "Cilium VXLAN"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = "+cluster-nodes"
    dport   = "4240"
    proto   = "tcp"
    comment = "Cilium healthcheck"
  }
}

resource "proxmox_virtual_environment_firewall_rules" "talos-worker" {
  for_each   = local.virtual_worker_nodes
  depends_on = [proxmox_virtual_environment_vm.talos-worker]

  node_name = each.key
  vm_id     = proxmox_virtual_environment_vm.talos-worker[each.key].vm_id

  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = "+cluster-nodes"
    dport   = "50000"
    proto   = "tcp"
    comment = "Talos API"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = "+cluster-nodes"
    dport   = "10250"
    proto   = "tcp"
    comment = "kubelet API"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = "+cluster-nodes"
    dport   = "8472"
    proto   = "udp"
    comment = "Cilium VXLAN"
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = "+cluster-nodes"
    dport   = "4240"
    proto   = "tcp"
    comment = "Cilium healthcheck"
  }
}
