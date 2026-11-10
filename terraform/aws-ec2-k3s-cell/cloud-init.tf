# The cloud-init document of the k3s VM. It installs a single-node k3s cluster
# and the Omnistrate dataplane agent.
#
# Omnistrate loads only Terraform files from a module in Git, so the document
# is a heredoc here instead of a separate template file. Shell variables are
# written as $${name} so that Terraform leaves them for bash.
#
# The k3s flags match `install.sh --create-k3s-cluster NAME
# --k3s-node-external-ip IP` from the BYOC on-prem install kit. The kernel
# modules and sysctls are the ones that k3s needs on Ubuntu 24.04.
locals {
  cloud_init = <<EOT
#cloud-config
ssh_authorized_keys: ${jsonencode(local.ssh_authorized_keys)}
write_files:
  - path: /etc/omnistrate/dp-agent-values.yaml
    owner: root:root
    permissions: "0600"
    encoding: b64
    content: ${var.agent_helm_values_base64}
%{if var.agent_registry_host != ""~}
  - path: /etc/omnistrate/dp-agent-registry-password
    owner: root:root
    permissions: "0600"
    content: ${jsonencode(var.agent_registry_password)}
  - path: /etc/omnistrate/dp-agent-registry-config.json
    owner: root:root
    permissions: "0600"
    encoding: b64
    content: ${var.agent_registry_docker_config_json_base64}
%{endif~}
  - path: /etc/modules-load.d/omnistrate-k3s.conf
    owner: root:root
    permissions: "0644"
    content: |
      overlay
      br_netfilter
      ip_tables
      iptable_nat
      iptable_filter
      nf_nat
      nf_conntrack
      vxlan
  - path: /etc/sysctl.d/99-omnistrate-k3s.conf
    owner: root:root
    permissions: "0644"
    content: |
      net.bridge.bridge-nf-call-iptables = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward = 1
  - path: /usr/local/bin/omnistrate-cell-bootstrap.sh
    owner: root:root
    permissions: "0700"
    content: |
      #!/bin/bash
      set -euo pipefail

      while read -r module; do
        modprobe "$${module}" || true
      done </etc/modules-load.d/omnistrate-k3s.conf
      sysctl --system

      imds_token="$(curl -fsS -X PUT http://169.254.169.254/latest/api/token \
        -H 'X-aws-ec2-metadata-token-ttl-seconds: 300')"
      imds() {
        curl -fsS -H "X-aws-ec2-metadata-token: $${imds_token}" \
          "http://169.254.169.254/latest/meta-data/$1"
      }
      private_ip="$(imds local-ipv4)"
      public_ip="$(imds public-ipv4 || true)"

      install_exec="--disable=traefik --write-kubeconfig-mode=600"
      install_exec="$${install_exec} --node-ip=$${private_ip} --advertise-address=$${private_ip}"
      if [ -n "$${public_ip}" ]; then
        install_exec="$${install_exec} --node-external-ip=$${public_ip} --tls-san=$${public_ip}"
      fi
      curl -fsSL --proto '=https' https://get.k3s.io \
        | INSTALL_K3S_VERSION="${var.k3s_version}" INSTALL_K3S_EXEC="$${install_exec}" sh -

      export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
      for _ in $(seq 1 60); do
        if kubectl get nodes -o name 2>/dev/null | grep -q .; then
          break
        fi
        sleep 5
      done
      kubectl wait --for=condition=Ready node --all --timeout=10m
      for deployment in coredns local-path-provisioner metrics-server; do
        for _ in $(seq 1 60); do
          if kubectl -n kube-system get deployment "$${deployment}" >/dev/null 2>&1; then
            break
          fi
          sleep 2
        done
        kubectl -n kube-system rollout status "deployment/$${deployment}" --timeout=5m
      done

      # The ubuntu user can run kubectl when it logs in over SSH.
      install -d -m 0700 -o ubuntu -g ubuntu /home/ubuntu/.kube
      install -m 0600 -o ubuntu -g ubuntu /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config

      case "$(uname -m)" in
        x86_64) arch=amd64 ;;
        aarch64) arch=arm64 ;;
        *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
      esac
      curl -fsSL --proto '=https' "https://get.helm.sh/helm-${var.helm_version}-linux-$${arch}.tar.gz" \
        | tar -xz -C /tmp "linux-$${arch}/helm"
      install -m 0755 "/tmp/linux-$${arch}/helm" /usr/local/bin/helm

%{if var.agent_registry_host != ""~}
      # The agent chart and image come from the service provider's private
      # registry. Helm logs in with a temporary registry configuration, and the
      # agent pulls its image with the pull secret. The credential files are
      # removed when the script exits.
      registry_workspace="$(mktemp -d)"
      trap 'rm -rf "$${registry_workspace}" /etc/omnistrate/dp-agent-registry-password /etc/omnistrate/dp-agent-registry-config.json' EXIT
      export HELM_REGISTRY_CONFIG="$${registry_workspace}/config.json"
      helm registry login "${var.agent_registry_host}" --username "${var.agent_registry_username}" \
        --password-stdin </etc/omnistrate/dp-agent-registry-password
      kubectl create namespace "${var.agent_namespace}" --dry-run=client -o yaml | kubectl apply -f -
      kubectl -n "${var.agent_namespace}" create secret generic "${var.agent_registry_pull_secret_name}" \
        --type=kubernetes.io/dockerconfigjson \
        --from-file=.dockerconfigjson=/etc/omnistrate/dp-agent-registry-config.json \
        --dry-run=client -o yaml | kubectl apply -f -
%{endif~}
      helm upgrade --install "${var.agent_release_name}" "${var.agent_chart_repository}" \
        --version "${var.agent_chart_version}" \
        --namespace "${var.agent_namespace}" --create-namespace \
        --values /etc/omnistrate/dp-agent-values.yaml \
        --set nameOverride=dp-agent \
        --timeout 10m0s \
        --wait
      kubectl -n "${var.agent_namespace}" wait --for=condition=Ready pod \
        --selector=app.kubernetes.io/instance="${var.agent_release_name}" \
        --timeout=10m
runcmd:
  - [/usr/local/bin/omnistrate-cell-bootstrap.sh]
EOT
}
