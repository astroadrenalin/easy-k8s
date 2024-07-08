terraform {
  required_providers {
    arvan = {
      source = "terraform.arvancloud.ir/arvancloud/iaas"
    }
  }
}

provider "arvan" {
  api_key = var.api_key
}

variable "region" {
  type        = string
  description = "The chosen region for resources"
  default     = "ir-thr-si1"
}

variable "chosen_distro_name" {
  type        = string
  description = "The chosen distro name for image"
  default     = "ubuntu"
}

variable "chosen_name" {
  type        = string
  description = "The chosen release for image"
  default     = "22.04"
}

variable "chosen_network_name" {
  type        = string
  description = "The chosen name of network"
  default     = "public204" //public202
}

variable "chosen_ssh_key" {
  type        = string
  description = "The chosen name of SSH Key"
  default     = "openstack-key" // Fuck this shit
}

variable "chosen_plan_id" {
  type        = string
  description = "The chosen ID of plan"
  default     = "eco-2-2-0"
}

data "arvan_images" "terraform_image" {
  region     = var.region
  image_type = "distributions" // Fuck off
}

data "arvan_plans" "plan_list" {
  region = var.region
}

locals {
  chosen_image = try(
    [for image in data.arvan_images.terraform_image.distributions : image
    if image.distro_name == var.chosen_distro_name && image.name == var.chosen_name],
    []
  )

  selected_plan = [for plan in data.arvan_plans.plan_list.plans : plan if plan.id == var.chosen_plan_id][0]
}

resource "arvan_security_group" "terraform_security_group" {
  region      = var.region
  description = "Terraform-created security group"
  name        = "tf_security_group"
  rules = [
    {
      direction = "ingress"
      protocol  = "icmp"
    },
    {
      direction = "ingress"
      protocol  = "udp"
    },
    {
      direction = "ingress"
      protocol  = "tcp"
    },
    {
      direction = "egress"
      protocol  = ""
    }
  ]
}

resource "arvan_network" "terraform_private_network" {
  region      = var.region
  description = "Terraform-created k8s private network"
  name        = "tf_private_network-1"
  dhcp_range = {
    start = "172.20.0.100"
    end   = "172.20.0.250"
  }
  dns_servers    = ["8.8.8.8", "1.1.1.1"]
  enable_dhcp    = true
  enable_gateway = true # Doesn't accept anything else (false, no, skip, etc...) - Need to ask Mina Mohammadi
  cidr           = "172.20.0.0/24"
  gateway_ip     = "172.20.0.1"
}


data "arvan_networks" "terraform_network" {
  region = var.region
}

locals {
  network_list = tolist(data.arvan_networks.terraform_network.networks)
  chosen_network = try(
    [for network in local.network_list : network
    if network.name == var.chosen_network_name],
    []
  )
}

output "chosen_network" {
  value = local.chosen_network
}

data "arvan_ssh_keys" "ssh_keys_list" {
  region = var.region
}

locals {
  ssh_key = tolist(data.arvan_ssh_keys.ssh_keys_list.keys)
  chosen_ssh_key = try(
    [for ssh_key in local.ssh_key : ssh_key
    if ssh_key.name == var.chosen_ssh_key],
    []
  )
}

output "chosen_ssh_key" {
  value = local.chosen_ssh_key
}

output "network_list" {
  value = data.arvan_networks.terraform_network.networks
}

resource "arvan_abrak" "built_by_terraform" {
  count = length(local.chosen_network) > 0 ? 3 : 0
  depends_on = [arvan_security_group.terraform_security_group, arvan_network.terraform_private_network]
  timeouts {
    create = "1h30m"
    update = "2h"
    delete = "20m"
    read   = "10m"
  }
  region    = var.region
  name      = "Kubernetes-Node"
  image_id  = length(local.chosen_image) > 0 ? local.chosen_image[0].id : ""
  flavor_id = local.selected_plan.id
  ssh_key_name = length(local.chosen_ssh_key) > 0 ? local.chosen_ssh_key[0].name : ""
  disk_size = 30
  networks = [
    {
      network_id = length(local.chosen_network) > 0 ? local.chosen_network[0].network_id : ""
    },
    {
      network_id = arvan_network.terraform_private_network.id
    }
  ]
  security_groups = [arvan_security_group.terraform_security_group.id]
}

  # private_networks = [arvan_network.terraform_private_network.id] --- Should not be used here --- Has been moved up into networks.


output "instances" {
  value = arvan_abrak.built_by_terraform
}
# Add an output for the IP of the server here 
# Alongside it, try to variablize it. Meaning
# it would give ubutnu@$SERVER_IP in the field
# for easier copy & pasting.
