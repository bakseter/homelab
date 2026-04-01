# Initial setup

## Install sshpass

```bash
pacman -S sshpass
```

## Generate key, if not exists

```bash
ssh-keygen -t ed25519 -C 'ansible-homelab' -f ~/.ssh/ansible_homelab
```

## Copy to any hosts that need it

```bash
ssh-copy-id -i ~/.ssh/ansible_homelab.pub root@192.168.1.xxx
```

## Run Ansible

This will disable password SSH.

```
ansible-playbook -i inventory.yaml site.yaml --check --diff
ansible-playbook -i inventory.yaml site.yaml
```
