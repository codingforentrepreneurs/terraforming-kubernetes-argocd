terraform {
    required_version = ">= 0.15"
    required_providers {
        linode = {
            source = "linode/linode"
        }
    }
}

provider "linode" {
    token = var.linode_api_token
}

locals {
    root_dir = "${dirname(abspath(path.root))}"
    k8s_config_dir = "${local.root_dir}/.kube/"
    k8s_config_file = "${local.root_dir}/.kube/kubeconfig.yaml"
}

variable "linode_api_token" {
    description = "Your Linode API Personal Access Token. (required)"
    sensitive   = true
}

resource "linode_lke_cluster" "tf_k8s_argocd" {
    k8s_version="1.25"
    label="tf-k8s-argocd"
    region="us-east"
    tags=["tf-k8s", "argcd"]
    pool {
        type  = "g6-standard-1"
        count = 3

    }
}

resource "local_file" "k8s_config" {
    content = "${nonsensitive(base64decode(linode_lke_cluster.tf_k8s_argocd.kubeconfig))}"
    filename = "${local.k8s_config_file}"
    file_permission = "0600"
}

