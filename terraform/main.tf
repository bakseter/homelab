provider "proxmox" {
  endpoint = "https://192.168.1.27:8006/"

  username = var.proxmox_username
  password = var.proxmox_password

  insecure = true
}
