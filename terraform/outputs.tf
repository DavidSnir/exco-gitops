output "cluster_name" {
  description = "Local kind cluster name."
  value       = kind_cluster.exco.name
}

output "kubeconfig_path" {
  description = "Local credentials file; never commit its contents."
  value       = kind_cluster.exco.kubeconfig_path
}

output "app_url" {
  description = "Ingress HTTP endpoint; returns 404 until Part 2 creates an app route."
  value       = "http://localhost:${var.app_port}"
}

output "argocd_port_forward" {
  description = "Run this locally, then open https://localhost:18081."
  value       = "kubectl --kubeconfig '${kind_cluster.exco.kubeconfig_path}' -n argocd port-forward svc/argocd-server 18081:443 --address 127.0.0.1"
}
