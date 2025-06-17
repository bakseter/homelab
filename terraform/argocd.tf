provider "helm" {
  kubernetes {
    host               = talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration.host
    client_certificate = base64decode(talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration.client_certificate)
    client_key         = base64decode(talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration.client_key)
    insecure           = true
  }
}

resource "helm_release" "argocd" {
  depends_on = [talos_cluster_kubeconfig.kubeconfig]

  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"

  create_namespace = true
  namespace        = "argocd"
}

locals {
  root_app_manifest = file("${path.module}/../manifests/bootstrap/bootstrap.yaml")
}

resource "null_resource" "kubectl-apply-bootstrap" {
  depends_on = [helm_release.argocd]

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
