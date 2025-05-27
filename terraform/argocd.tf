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
