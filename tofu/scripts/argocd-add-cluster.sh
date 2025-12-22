#!/bin/bash

if [[ -z "$KUBECONFIG" ]]; then
  echo "Error: KUBECONFIG environment variable must be set."
  exit 1
fi

kubectl -n argocd port-forward svc/argocd-server 8080:443 --kubeconfig <(echo "$KUBECONFIG" | base64 -d) &
PORT_FORWARD_PID=$!
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret --kubeconfig <(echo "$KUBECONFIG" | base64 -d) -o jsonpath="{.data.password}" | base64 -d)

sleep 5

argocd login localhost:8080 --username admin --password "$ARGOCD_PASSWORD" --insecure
argocd cluster add admin@homelab -y --kubeconfig <(echo "$KUBECONFIG" | base64 -d)

kill "$PORT_FORWARD_PID"
