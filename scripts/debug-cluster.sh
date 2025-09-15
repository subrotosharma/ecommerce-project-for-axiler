#!/bin/bash
# Debug script I created during development to quickly check cluster health

echo "=== EKS Cluster Health Check ==="
echo "Cluster: $(kubectl config current-context)"
echo "Date: $(date)"
echo

echo "=== Node Status ==="
kubectl get nodes -o wide
echo

echo "=== Pod Status by Namespace ==="
for ns in default monitoring argocd ingress-nginx; do
    echo "--- Namespace: $ns ---"
    kubectl get pods -n $ns --no-headers 2>/dev/null | grep -v Running | head -5
    running_count=$(kubectl get pods -n $ns --no-headers 2>/dev/null | grep Running | wc -l)
    total_count=$(kubectl get pods -n $ns --no-headers 2>/dev/null | wc -l)
    echo "Running: $running_count/$total_count pods"
    echo
done

echo "=== Service Status ==="
kubectl get svc --all-namespaces | grep -E "(LoadBalancer|NodePort)"
echo

echo "=== Ingress Status ==="
kubectl get ingress --all-namespaces
echo

echo "=== Certificate Status ==="
kubectl get certificates --all-namespaces
echo

echo "=== Recent Events (Last 10) ==="
kubectl get events --sort-by='.lastTimestamp' --all-namespaces | tail -10
echo

echo "=== Resource Usage ==="
echo "--- Top Nodes ---"
kubectl top nodes 2>/dev/null || echo "Metrics server not available"
echo "--- Top Pods (CPU) ---"
kubectl top pods --all-namespaces --sort-by=cpu 2>/dev/null | head -10 || echo "Metrics server not available"
echo

echo "=== Storage Status ==="
kubectl get pv,pvc --all-namespaces
echo

echo "=== ArgoCD Application Status ==="
kubectl get applications -n argocd 2>/dev/null || echo "ArgoCD not installed"
echo

echo "=== Quick Connectivity Test ==="
echo "Testing internal DNS resolution..."
kubectl run test-dns --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default.svc.cluster.local 2>/dev/null || echo "DNS test failed"

echo "=== Health Check Complete ==="