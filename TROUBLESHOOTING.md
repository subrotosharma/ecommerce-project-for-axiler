# Troubleshooting Guide

## Common Issues I Encountered During Development

### 1. EKS Node Group Not Joining Cluster

**Problem:** Nodes showing as "NotReady" status
```bash
kubectl get nodes
# NAME                          STATUS     ROLES    AGE   VERSION
# ip-10-0-1-100.ec2.internal   NotReady   <none>   5m    v1.28.0
```

**Root Cause:** Security group rules not allowing communication between control plane and worker nodes.

**Solution:** Added proper security group rules in Terraform:
```hcl
# Allow communication between control plane and worker nodes
resource "aws_security_group_rule" "cluster_ingress_workstation_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}
```

### 2. Ingress Not Receiving External Traffic

**Problem:** Services accessible internally but not from internet
```bash
curl https://axiler.subrotosharma.site
# curl: (7) Failed to connect to axiler.subrotosharma.site port 443: Connection refused
```

**Debugging Steps:**
1. Check ingress controller pods: `kubectl get pods -n ingress-nginx`
2. Check service type: `kubectl get svc -n ingress-nginx`
3. Verify LoadBalancer has external IP: `kubectl get svc ingress-nginx-controller -n ingress-nginx`

**Solution:** LoadBalancer service wasn't created properly. Fixed by reinstalling ingress controller:
```bash
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer
```

### 3. ArgoCD Sync Failures

**Problem:** Applications stuck in "OutOfSync" status with errors
```
Error: admission webhook "validate.nginx.ingress.kubernetes.io" denied the request: 
host "_" and path "/" is already defined in ingress default/ecommerce-https-ingress
```

**Investigation Process:**
1. Checked ArgoCD application logs
2. Found duplicate ingress resources
3. Identified conflicting host/path combinations

**Solution:** Removed duplicate ingress definitions and ensured unique host/path combinations.

### 4. SSL Certificate Issues

**Problem:** Certificates not being issued by Let's Encrypt
```bash
kubectl get certificates
# NAME           READY   SECRET         AGE
# ecommerce-tls  False   ecommerce-tls  10m
```

**Debugging:**
```bash
kubectl describe certificate ecommerce-tls
# Events show DNS validation failures
```

**Root Cause:** DNS records not pointing to correct LoadBalancer

**Solution:** Updated Route 53 records to point to ingress LoadBalancer:
```bash
aws route53 change-resource-record-sets --hosted-zone-id Z04439106WYRY5ZWG75C \
  --change-batch file://dns-update.json
```

### 5. Prometheus Not Scraping Metrics

**Problem:** No metrics showing in Grafana dashboards

**Investigation:**
1. Checked Prometheus targets: `http://prometheus.subrotosharma.site/targets`
2. Found services not being discovered
3. Missing service monitor labels

**Solution:** Added proper labels to services:
```yaml
metadata:
  labels:
    app: ecommerce-frontend
    monitoring: "true"  # This label is required for service discovery
```

### 6. High Memory Usage Causing Pod Restarts

**Problem:** Pods getting OOMKilled frequently
```bash
kubectl describe pod ecommerce-frontend-xxx
# Last State: Terminated
# Reason: OOMKilled
```

**Analysis:** No resource limits set, pods consuming all available memory

**Solution:** Added resource limits and requests:
```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

### 7. Database Connection Failures

**Problem:** Applications couldn't connect to RDS database
```
Error: dial tcp 10.0.3.100:5432: i/o timeout
```

**Debugging Steps:**
1. Checked security groups on RDS instance
2. Verified subnet group configuration
3. Tested connectivity from worker nodes

**Solution:** Updated RDS security group to allow traffic from EKS worker nodes:
```hcl
resource "aws_security_group_rule" "rds_ingress" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_eks_node_group.main.resources[0].remote_access_security_group_id
  security_group_id        = aws_security_group.rds.id
}
```

## Useful Debugging Commands

### Kubernetes Troubleshooting
```bash
# Check pod logs
kubectl logs -f deployment/ecommerce-frontend

# Describe pod for events
kubectl describe pod <pod-name>

# Check service endpoints
kubectl get endpoints

# Test service connectivity
kubectl run test-pod --image=busybox -it --rm -- /bin/sh
# Inside pod: wget -qO- http://service-name:port

# Check ingress status
kubectl describe ingress ecommerce-https-ingress
```

### AWS Troubleshooting
```bash
# Check EKS cluster status
aws eks describe-cluster --name ecommerce-eks-dev

# List node groups
aws eks describe-nodegroup --cluster-name ecommerce-eks-dev --nodegroup-name main

# Check LoadBalancer status
aws elbv2 describe-load-balancers
```

### Terraform Troubleshooting
```bash
# Check current state
terraform show

# Validate configuration
terraform validate

# Plan with detailed output
terraform plan -detailed-exitcode

# Import existing resources
terraform import aws_instance.example i-1234567890abcdef0
```

## Performance Optimization Tips Learned

### 1. Resource Right-sizing
Monitor actual usage and adjust requests/limits accordingly:
```bash
kubectl top pods
kubectl top nodes
```

### 2. Image Optimization
Use multi-stage Docker builds to reduce image size:
```dockerfile
# Build stage
FROM node:16 AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# Runtime stage
FROM node:16-alpine
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY . .
CMD ["npm", "start"]
```

### 3. Horizontal Pod Autoscaling
Configure HPA based on actual load patterns:
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ecommerce-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ecommerce-frontend
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

## Lessons Learned

1. **Always check logs first** - Most issues can be diagnosed from pod/service logs
2. **Use describe commands** - Kubernetes events provide valuable debugging information
3. **Test incrementally** - Deploy and test one component at a time
4. **Monitor resource usage** - Set appropriate limits to prevent resource starvation
5. **Document solutions** - Keep track of fixes for future reference
6. **Use staging environment** - Test changes before applying to production
7. **Backup before major changes** - Always have a rollback plan