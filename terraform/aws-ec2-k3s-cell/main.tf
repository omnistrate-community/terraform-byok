# Creates a single-node k3s cluster on an EC2 VM and installs the Omnistrate
# dataplane agent on it, so that the VM becomes the BYOC on-prem cell of the
# deployment. Omnistrate runs this module from the cellInfra resource of the
# plans in ../../specs.
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

# Credentials come from the environment. The dataplane agent on the provisioner
# host cluster runs OpenTofu under the service account of the BYOC on-prem
# account instance and assumes the customer role from
# terraformExecutionIdentity with sts:AssumeRoleWithWebIdentity.
provider "aws" {
  region = var.region

  default_tags {
    tags = merge(var.extra_tags, local.tags)
  }
}

locals {
  name = "omnistrate-cell-${var.deployment_id}"

  tags = {
    "omnistrate-cell"       = var.cell_name
    "omnistrate-deployment" = var.deployment_id
  }

  ssh_authorized_keys = [for key in split(",", var.ssh_authorized_keys) : trimspace(key) if trimspace(key) != ""]
  ingress_cidrs       = [for cidr in split(",", var.ingress_cidrs) : trimspace(cidr) if trimspace(cidr) != ""]
  ingress_ports       = length(local.ingress_cidrs) > 0 ? var.ingress_ports : []

  subnet_id = var.subnet_id != "" ? var.subnet_id : sort(data.aws_subnets.default[0].ids)[0]
}

data "aws_vpc" "default" {
  count   = var.subnet_id == "" ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = var.subnet_id == "" ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_subnet" "selected" {
  id = local.subnet_id
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# The agent only opens outbound connections. Inbound rules exist only when the
# caller sets ingress_cidrs.
resource "aws_security_group" "cell" {
  name        = local.name
  description = "Omnistrate BYOC on-prem cell ${var.cell_name}"
  vpc_id      = data.aws_subnet.selected.vpc_id

  dynamic "ingress" {
    for_each = local.ingress_ports
    content {
      description = "Access to the cell from ingress_cidrs"
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = "tcp"
      cidr_blocks = local.ingress_cidrs
    }
  }

  egress {
    description = "Outbound access to the Omnistrate control plane and registries"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "k3s" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnet.selected.id
  vpc_security_group_ids      = [aws_security_group.cell.id]
  associate_public_ip_address = var.associate_public_ip

  user_data_base64 = base64gzip(templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    ssh_authorized_keys                      = local.ssh_authorized_keys
    k3s_version                              = var.k3s_version
    helm_version                             = var.helm_version
    agent_chart_repository                   = var.agent_chart_repository
    agent_chart_version                      = var.agent_chart_version
    agent_namespace                          = var.agent_namespace
    agent_release_name                       = var.agent_release_name
    agent_helm_values_base64                 = var.agent_helm_values_base64
    agent_registry_host                      = var.agent_registry_host
    agent_registry_username                  = var.agent_registry_username
    agent_registry_password                  = var.agent_registry_password
    agent_registry_docker_config_json_base64 = var.agent_registry_docker_config_json_base64
    agent_registry_pull_secret_name          = var.agent_registry_pull_secret_name
  }))

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = local.name
  }

  # The bootstrap runs once at first boot. Later changes to the rendered agent
  # values or to the AMI must not replace the cell's only node. Agent upgrades
  # go through the control plane after the agent connects.
  lifecycle {
    ignore_changes = [user_data_base64, ami]
  }
}
