# The chart contains only an Application CR. Argo CD, not Terraform/Helm,
# creates the Deployment, Service and Ingress from the git repository.
# Using Helm avoids kubernetes_manifest's plan-time CRD discovery problem.
resource "helm_release" "bootstrap" {
  name      = "exco-bootstrap"
  namespace = "argocd"
  chart     = "${path.module}/charts/bootstrap"
  version   = "0.1.0"
  values    = [file("${path.module}/charts/bootstrap/values.yaml")]

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 300
  max_history     = 3

  # Argo CD's CRD and controller must exist before the Application is created,
  # and remain available while its cascading-deletion finalizer runs.
  depends_on = [helm_release.argocd, helm_release.traefik]

  lifecycle {
    replace_triggered_by = [kind_cluster.exco]
  }
}
