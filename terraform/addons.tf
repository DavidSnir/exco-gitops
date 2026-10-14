resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.10.3"
  values           = [file("${path.module}/values/argocd.yaml")]

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  wait_for_jobs   = true
  timeout         = 600
  max_history     = 3

  # Also ensures destroy uninstalls the chart before deleting the cluster.
  depends_on = [kind_cluster.exco]

  lifecycle {
    replace_triggered_by = [kind_cluster.exco]
  }
}

resource "helm_release" "traefik" {
  name             = "traefik"
  namespace        = "traefik"
  create_namespace = true
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = "41.7.1"
  values           = [file("${path.module}/values/traefik.yaml")]

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  wait_for_jobs   = true
  timeout         = 600
  max_history     = 3

  depends_on = [kind_cluster.exco]

  lifecycle {
    replace_triggered_by = [kind_cluster.exco]
  }
}
