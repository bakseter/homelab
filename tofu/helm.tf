provider "helm" {
  kubernetes = {
    host               = talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration.host
    client_certificate = base64decode(talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration.client_certificate)
    client_key         = base64decode(talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration.client_key)
    insecure           = true
  }
}

resource "helm_release" "cilium" {
  depends_on = [talos_machine_bootstrap.bootstrap]

  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  namespace  = "kube-system"

  atomic        = true
  force_update = true

  set = [
    {
      name  = "ipam.mode"
      value = "kubernetes"
    },
    {
      name  = "kubeProxyReplacement"
      value = "true"
    },
    {
      name  = "securityContext.capabilities.ciliumAgent"
      value = "{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}"
    },
    {
      name  = "securityContext.capabilities.cleanCiliumState"
      value = "{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}"
    },
    {
      name  = "cgroup.autoMount.enabled"
      value = "false"
    },
    {
      name  = "cgroup.hostRoot"
      value = "/sys/fs/cgroup"
    },
    {
      name  = "k8sServiceHost"
      value = "localhost"
    },
    {
      name  = "k8sServicePort"
      value = "7445"
    },
    {
      name  = "socketLB.hostNamespaceOnly"
      value = "true"
    }
  ]
}

resource "helm_release" "argocd" {
  depends_on = [helm_release.cilium]

  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"

  create_namespace = true
  namespace        = "argocd"
}

resource "null_resource" "argocd-add-cluster" {
  depends_on = [helm_release.argocd]

  provisioner "local-exec" {
    command     = "echo \"$SCRIPT\" > /tmp/argocd-add-cluster.sh && chmod +x /tmp/argocd-add-cluster.sh && bash /tmp/argocd-add-cluster.sh"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = base64encode(talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw)
      SCRIPT     = file("${path.module}/scripts/argocd-add-cluster.sh")
    }
  }
}

locals {
  root_app_manifest = file("${path.module}/../manifests/root.yaml")
}

resource "null_resource" "kubectl-apply-root" {
  depends_on = [null_resource.argocd-add-cluster]

  triggers = {
    manifest    = local.root_app_manifest
    helm_argocd = helm_release.argocd.id
  }

  provisioner "local-exec" {
    command     = "kubectl apply --force --kubeconfig <(echo \"$KUBECONFIG\" | base64 -d) -f <(echo \"$MANIFEST\" | base64 -d)"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = base64encode(talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw)
      MANIFEST   = base64encode(local.root_app_manifest)
    }
  }
}
