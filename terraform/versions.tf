terraform {
  required_version = ">= 1.5, < 2.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "0.11.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.3.0"
    }
  }
}

provider "kind" {}

# Credentials come from the cluster resource, not a file that is missing
# during the first plan. No dependency on the laptop's current kube context.
provider "helm" {
  kubernetes = {
    host                   = kind_cluster.exco.endpoint
    client_certificate     = kind_cluster.exco.client_certificate
    client_key             = sensitive(kind_cluster.exco.client_key)
    cluster_ca_certificate = kind_cluster.exco.cluster_ca_certificate
  }
}
