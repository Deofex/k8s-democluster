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
kubectl create ns nginx-shared-gateway
openssl genrsa -out cert_key.pem 2048
openssl req -new -key cert_key.pem -out cert_csr.pem -subj "/CN=argocd.local"
openssl x509 -req -in cert_csr.pem -sha256 -days 365 -extensions v3_ca -signkey cert_key.pem -CAcreateserial -out cert_cert.pem
kubectl create secret tls argocd-server-tls --key="cert_key.pem" --cert="cert_cert.pem" -n nginx-shared-gateway
rm cert_key.pem  cert_cert.pem cert_csr.pem

# Create user account with the password Welkom01:
kubectl patch configmap argocd-cm -n argocd \
  --type='json' -p='[{"op": "add", "path": "/data/accounts.user", "value": "login"}]'
kubectl patch configmap argocd-cm -n argocd --type merge -p '
{
  "data": {
    "oidc.config": "name: Keycloak\nissuer: http://usermanagement.local/realms/master\nclientID: argocd\nclientSecret: $oidc.keycloak.clientSecret\nrequestedScopes: [\"openid\", \"profile\", \"email\", \"groups\"]"
  }
}'
kubectl patch secret argocd-secret   -n argocd \
  --type='json' -p='[{"op": "add", "path": "/data/accounts.user.password", "value": "JDJhJDEwJFBxNGVrd2dyMTV5QjRSSlFZZkNvbi5CR1dlSXBINTBtNklYMVNkNjBrLnhrSmFScFZZVE1P"}]'
kubectl patch secret argocd-secret   -n argocd \
  --type='json' -p='[{"op": "add", "path": "/data/accounts.user.passwordMtime", "value": "MjAyNC0wNy0zMVQxMDozNDoyM1o="}]'
kubectl patch secret argocd-secret   -n argocd \
  --type='json' -p='[{"op": "add", "path": "/data/accounts.user.tokens", "value": "bnVsbA=="}]'
kubectl patch secret argocd-secret   -n argocd \
  --type='json' -p='[{"op": "add", "path": "/data/oidc.keycloak.clientSecret", "value": "z9lfNxP8nG0XnufpjqPCQ8vsGVkezjR2"}]'
kubectl patch cm argocd-cm -n argocd --type merge -p '{"data":{"url":"https://argocd.local"}}'
kubectl rollout restart deployment argocd-server -n argocd

# Apply new coredns config
kubectl apply -f argocd/init/coredns-cm.yaml 
kubectl rollout restart deployment coredns -n kube-system

# Provide credentials to user
echo "ARGO CD is accessible with the following credentials: \"admin\", password: \"$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)\""

