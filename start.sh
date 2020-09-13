#!/usr/bin/env zsh
set -x
set -o pipefail
# Helper function to run scripts on multibe nodes

footloose_run() {
  TYPE=$1
  COMMAND=$2
  TYPES=""
  if [[ "${TYPE}" == "all" ]]
  then
    TYPES=$(cat footloose.yaml | yq -r '.machines[].spec.name' | sed 's/%d//g' | tr '\n' ' ')
  else
    TYPES=${TYPE}
  fi

  for SERVER_TYPE in $(echo $TYPES)
  do
    count=$(cat footloose.yaml | yq '.machines[]' | sed 's/%d//g'| jq "{count: .count, name: .spec.name} | select(.name==\"${SERVER_TYPE}\")" | jq .count)
    count="$(($count-1))"
    for i in {0..$count}
    do
      footloose ssh root@${SERVER_TYPE}${i} "${COMMAND}"
    done
  done
}

# Create footloose cluster
footloose create

# Letting iptables see bridged traffic
footloose_run all "cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system"


# disable dns caching # Fixing bug here https://coredns.io/plugins/loop/#troubleshooting
footloose_run all "systemctl stop systemd-resolved && systemctl disable systemd-resolved"
footloose_run all "echo 'nameserver 8.8.8.8' > /etc/resolv.conf"

# Enabling kernel netfilter module (already enabled on the image)
# footloose_run all "modprobe br_netfilter"

# Installing docker on all nodes
footloose_run all "curl -L https://get.docker.io | bash -"
footloose_run all "service docker start"

# Install kernel image package
footloose_run all 'apt-get install -y -qq linux-image-$(uname -r)'

# Install kubelet, kubectl, kubeadm
footloose_run all "sudo apt-get update && sudo apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
sudo apt-get -qq update
sudo apt-get install -y -qq kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl"

# Launch kubernetes control plane

KUBEADM_TOKEN=$(footloose ssh root@master0 kubeadm token generate)
APISERVER_ADVERTISE_ADDRESS=$(footloose ssh root@master0 ifconfig eth0 | grep inet | awk '{print $2}')

footloose ssh  root@master0 "kubeadm init --pod-network-cidr 10.244.0.0/16 \
                            --apiserver-advertise-address ${APISERVER_ADVERTISE_ADDRESS} \
                            --token ${KUBEADM_TOKEN}"

footloose ssh  root@master0 'mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config'

# apply network CNI Plugin
footloose_run master $'kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d \'\n\')"'

# Generate kube-adm token for the workers to join master
DISCOVERY_TOKEN_CA_CERT_HASH="$(footloose ssh  root@master0 $'openssl x509 -in /etc/kubernetes/pki/ca.crt -noout -pubkey | openssl rsa -pubin -outform DER 2>/dev/null | sha256sum | cut -d\' \' -f1')"

footloose_run worker "kubeadm join ${APISERVER_ADVERTISE_ADDRESS}:6443 --token ${KUBEADM_TOKEN} \
                     --discovery-token-ca-cert-hash sha256:${DISCOVERY_TOKEN_CA_CERT_HASH}"
