variable "cluster_name" {
  description = "Name of the local kind cluster. Changing it recreates the cluster."
  type        = string
  default     = "exco"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.cluster_name))
    error_message = "Use lowercase letters, numbers and hyphens for the cluster name."
  }
}

variable "app_port" {
  description = "Loopback HTTP port for the ingress controller; 8080 is occupied on this laptop."
  type        = number
  default     = 18080

  validation {
    condition     = var.app_port >= 1024 && var.app_port <= 65535 && floor(var.app_port) == var.app_port
    error_message = "Choose an integer TCP port between 1024 and 65535."
  }
}
