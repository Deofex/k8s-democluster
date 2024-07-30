#!/bin/bash
HELM_CHART_VERSION=7.3.11

## Install kind cluster
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 80
    protocol: TCP
  - containerPort: 30443
    hostPort: 443
    protocol: TCP
EOF

# Add ArgoCD + initial repo + initial app
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd --version $HELM_CHART_VERSION --create-namespace -n argocd -f argocd/init/values.yaml --wait
kubectl apply -f argocd/init/repo.yaml 
kubectl apply -f argocd/init/masterapp.yaml

# Create self signed certificate and add it to k8s, this will be used by the ingress controller
openssl genrsa -out cert_key.pem 2048
openssl req -new -key cert_key.pem -out cert_csr.pem -subj "/CN=argocd.local"
openssl x509 -req -in cert_csr.pem -sha256 -days 365 -extensions v3_ca -signkey cert_key.pem -CAcreateserial -out cert_cert.pem
kubectl create secret tls argocd-server-tls --key="cert_key.pem" --cert="cert_cert.pem" -n nginx-shared-gateway
rm cert_key.pem  cert_cert.pem cert_csr.pem

# Provide credentials to user
echo "ARGO CD is accessible with the following credentials: \"admin\", password: \"$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)\""

