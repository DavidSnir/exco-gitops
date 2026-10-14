resource "kind_cluster" "exco" {
  name            = var.cluster_name
  wait_for_ready  = true
  kubeconfig_path = abspath("${path.module}/kubeconfig")

  # The provider embeds kind 0.31.0. Use a patched Kubernetes 1.35 image,
  # compatible with the installed kubectl 1.36 (one-minor version skew).
  # Multi-architecture digest from the official kind 0.33.0 release notes.
  node_image = "kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0"

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    networking {
      api_server_address = "127.0.0.1"
    }

    node {
      role = "control-plane"

      # This must match ports.web.nodePort in values/traefik.yaml.
      extra_port_mappings {
        container_port = 30080
        host_port      = var.app_port
        listen_address = "127.0.0.1"
        protocol       = "TCP"
      }
    }

    node {
      role = "worker"
    }

    node {
      role = "worker"
    }
  }
}
