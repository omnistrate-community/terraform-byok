variable "deployment_id" {
  description = "Omnistrate deployment instance ID, used for names and tags."
  type        = string
}

variable "cell_name" {
  description = "Name of the BYOC on-prem cell that the agent registers as."
  type        = string
}

variable "region" {
  description = "AWS region of the k3s VM."
  type        = string
}

variable "subnet_id" {
  description = "Subnet for the k3s VM. An empty value selects a default subnet of the default VPC. The subnet needs outbound internet access."
  type        = string
  default     = ""
}

variable "associate_public_ip" {
  description = "Assign a public IP to the VM. The public IP becomes the k3s node external IP."
  type        = bool
  default     = true
}

variable "instance_type" {
  description = "EC2 instance type for the k3s node."
  type        = string
  default     = "t3.2xlarge"
}

variable "root_volume_size_gb" {
  description = "Root volume size in GiB."
  type        = number
  default     = 80
}

variable "k3s_version" {
  description = "k3s release to install."
  type        = string
  default     = "v1.33.11+k3s1"
}

variable "helm_version" {
  description = "Helm release used on the VM to install the agent chart."
  type        = string
  default     = "v3.15.4"
}

variable "agent_chart_repository" {
  description = "Dataplane agent chart reference, from $sys.deploymentCell.customerDeploymentCell.agent.chart.repository."
  type        = string
}

variable "agent_chart_version" {
  description = "Dataplane agent chart version, from $sys.deploymentCell.customerDeploymentCell.agent.chart.version."
  type        = string
}

variable "agent_namespace" {
  description = "Namespace for the dataplane agent, from $sys.deploymentCell.customerDeploymentCell.agent.namespace."
  type        = string
  default     = "dataplane-agent"
}

variable "agent_release_name" {
  description = "Helm release name for the dataplane agent, from $sys.deploymentCell.customerDeploymentCell.agent.releaseName."
  type        = string
  default     = "dp-agent"
}

variable "agent_helm_values_base64" {
  description = "Base64-encoded Helm values for the dataplane agent, from $sys.deploymentCell.customerDeploymentCell.agent.helmValuesBase64. The values contain the agent client key."
  type        = string
  sensitive   = true
}

variable "agent_registry_host" {
  description = "Host of the service provider's private registry, from $sys.deploymentCell.customerDeploymentCell.agent.registry.host. Set the agent_registry_* variables only in a spec for a service provider whose agent chart and image come from its private registry. An empty value installs the chart without a registry login."
  type        = string
  default     = ""
}

variable "agent_registry_username" {
  description = "Registry user name, from $sys.deploymentCell.customerDeploymentCell.agent.registry.username."
  type        = string
  default     = ""
}

variable "agent_registry_password" {
  description = "Registry password, from $sys.deploymentCell.customerDeploymentCell.agent.registry.password. It is a short-lived ECR token."
  type        = string
  default     = ""
  sensitive   = true
}

variable "agent_registry_docker_config_json_base64" {
  description = "Base64-encoded dockerconfigjson document with the registry credentials, from $sys.deploymentCell.customerDeploymentCell.agent.registry.dockerConfigJSONBase64."
  type        = string
  default     = ""
  sensitive   = true
}

variable "agent_registry_pull_secret_name" {
  description = "Name of the image pull secret that the agent Helm values reference, from $sys.deploymentCell.customerDeploymentCell.agent.registry.pullSecretName."
  type        = string
  default     = ""
}

# The variables below are optional. Their defaults leave the VM with no SSH
# keys and no inbound rules. The agent needs only outbound access.

variable "ssh_authorized_keys" {
  description = "Comma-separated SSH public keys for the ubuntu user. The ubuntu user has a kubeconfig for the k3s cluster."
  type        = string
  default     = ""
}

variable "ingress_cidrs" {
  description = "Comma-separated IPv4 CIDRs that may reach the ingress ports. An empty value creates no inbound rules."
  type        = string
  default     = ""
}

variable "ingress_ports" {
  description = "TCP port ranges that ingress_cidrs may reach."
  type = list(object({
    from_port = number
    to_port   = number
  }))
  default = [
    { from_port = 22, to_port = 22 },
    { from_port = 80, to_port = 80 },
    { from_port = 443, to_port = 443 },
    { from_port = 30000, to_port = 32767 },
  ]
}

variable "extra_tags" {
  description = "Additional tags for every resource."
  type        = map(string)
  default     = {}
}
