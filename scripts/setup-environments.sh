#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENTS=("dev" "staging" "production")
BASE_NAMESPACE="microservices"
ARGOCD_NAMESPACE="argocd"

echo -e "${BLUE}🚀 Setting up Environment Namespaces for GitOps Pipeline${NC}"
echo "======================================================="

# Function to print status
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if kubectl is available and cluster is running
if ! kubectl cluster-info &> /dev/null; then
    print_error "Kubernetes cluster is not accessible. Please ensure Minikube is running."
    exit 1
fi

print_status "Kubernetes cluster is accessible"

# Function to create namespace with all configurations
create_environment_namespace() {
    local env=$1
    local namespace="${BASE_NAMESPACE}-${env}"
    
    echo -e "${BLUE}📦 Setting up $env environment ($namespace)...${NC}"
    
    # Create namespace
    kubectl apply -f - << EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $namespace
  labels:
    environment: $env
    app.kubernetes.io/name: microservices
    app.kubernetes.io/environment: $env
    managed-by: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
EOF

    print_status "Namespace $namespace created"
    
    # Create resource quota based on environment
    local cpu_requests="2"
    local memory_requests="4Gi"
    local cpu_limits="4"
    local memory_limits="8Gi"
    local pvc_count="5"
    
    # Adjust resources based on environment
    case $env in
        "dev")
            cpu_requests="1"
            memory_requests="2Gi"
            cpu_limits="2"
            memory_limits="4Gi"
            pvc_count="3"
            ;;
        "staging")
            cpu_requests="2"
            memory_requests="4Gi"
            cpu_limits="4"
            memory_limits="8Gi"
            pvc_count="4"
            ;;
        "production")
            cpu_requests="4"
            memory_requests="8Gi"
            cpu_limits="8"
            memory_limits="16Gi"
            pvc_count="6"
            ;;
    esac
    
    kubectl apply -f - << EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ${env}-resource-quota
  namespace: $namespace
  labels:
    environment: $env
spec:
  hard:
    requests.cpu: "$cpu_requests"
    requests.memory: "$memory_requests"
    limits.cpu: "$cpu_limits"
    limits.memory: "$memory_limits"
    persistentvolumeclaims: "$pvc_count"
    pods: "20"
    services: "10"
    secrets: "20"
    configmaps: "20"
EOF

    print_status "Resource quota applied for $env environment"
    
    # Create limit range
    kubectl apply -f - << EOF
apiVersion: v1
kind: LimitRange
metadata:
  name: ${env}-limit-range
  namespace: $namespace
  labels:
    environment: $env
spec:
  limits:
  - default:
      cpu: "500m"
      memory: "512Mi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    type: Container
  - default:
      storage: "10Gi"
    type: PersistentVolumeClaim
EOF

    print_status "Limit range applied for $env environment"
    
    # Create network policy for environment isolation
    kubectl apply -f - << EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${env}-network-policy
  namespace: $namespace
  labels:
    environment: $env
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Allow traffic from ArgoCD namespace
  - from:
    - namespaceSelector:
        matchLabels:
          name: $ARGOCD_NAMESPACE
  # Allow traffic within the same namespace
  - from:
    - namespaceSelector:
        matchLabels:
          name: $namespace
  # Allow traffic from ingress controller
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
  egress:
  # Allow all egress traffic (can be restricted further if needed)
  - {}
  # Allow DNS
  - to: []
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
EOF

    print_status "Network policy applied for $env environment"
    
    # Create service account for ArgoCD
    kubectl apply -f - << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-${env}
  namespace: $namespace
  labels:
    environment: $env
    app.kubernetes.io/name: argocd-service-account
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argocd-${env}-role
  namespace: $namespace
  labels:
    environment: $env
rules:
- apiGroups: [""]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["apps"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["networking.k8s.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["extensions"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["autoscaling"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: argocd-${env}-binding
  namespace: $namespace
  labels:
    environment: $env
subjects:
- kind: ServiceAccount
  name: argocd-${env}
  namespace: $namespace
- kind: ServiceAccount
  name: argocd-application-controller
  namespace: $ARGOCD_NAMESPACE
- kind: ServiceAccount
  name: argocd-server
  namespace: $ARGOCD_NAMESPACE
roleRef:
  kind: Role
  name: argocd-${env}-role
  apiGroup: rbac.authorization.k8s.io
EOF

    print_status "Service account and RBAC configured for $env environment"
    
    # Create environment-specific ConfigMap
    kubectl apply -f - << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${env}-config
  namespace: $namespace
  labels:
    environment: $env
    app.kubernetes.io/name: environment-config
data:
  ENVIRONMENT: "$env"
  NAMESPACE: "$namespace"
  LOG_LEVEL: "$([ "$env" = "production" ] && echo "info" || echo "debug")"
  DEBUG: "$([ "$env" = "production" ] && echo "false" || echo "true")"
  NODE_ENV: "$([ "$env" = "production" ] && echo "production" || echo "development")"
EOF

    print_status "Environment ConfigMap created for $env"
    
    # Create default secret template (to be populated later)
    kubectl apply -f - << EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${env}-secrets
  namespace: $namespace
  labels:
    environment: $env
    app.kubernetes.io/name: environment-secrets
type: Opaque
data:
  # Base64 encoded placeholder values
  DB_PASSWORD: cGFzc3dvcmQ=  # password
  API_SECRET: c2VjcmV0a2V5  # secretkey
  # Add more secrets as needed
EOF

    print_status "Secret template created for $env environment"
    
    echo -e "${GREEN}✅ $env environment setup completed${NC}"
    echo ""
}

# Create all environments
for env in "${ENVIRONMENTS[@]}"; do
    create_environment_namespace "$env"
done

# Create monitoring namespace for observability
echo -e "${BLUE}📊 Setting up monitoring namespace...${NC}"
kubectl apply -f - << EOF
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    name: monitoring
    app.kubernetes.io/name: monitoring
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: monitoring-quota
  namespace: monitoring
spec:
  hard:
    requests.cpu: "2"
    requests.memory: "4Gi"
    limits.cpu: "4"
    limits.memory: "8Gi"
    persistentvolumeclaims: "5"
EOF

print_status "Monitoring namespace created"

# Create cluster-wide RBAC for ArgoCD to manage all environments
echo -e "${BLUE}🔐 Setting up cluster-wide RBAC for ArgoCD...${NC}"
kubectl apply -f - << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-microservices-manager
  labels:
    app.kubernetes.io/name: argocd-microservices-manager
rules:
- apiGroups: [""]
  resources: ["namespaces", "configmaps", "secrets", "services", "persistentvolumeclaims", "pods"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "statefulsets", "daemonsets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses", "networkpolicies"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["autoscaling"]
  resources: ["horizontalpodautoscalers"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["roles", "rolebindings"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-microservices-manager
  labels:
    app.kubernetes.io/name: argocd-microservices-manager
subjects:
- kind: ServiceAccount
  name: argocd-application-controller
  namespace: $ARGOCD_NAMESPACE
- kind: ServiceAccount
  name: argocd-server
  namespace: $ARGOCD_NAMESPACE
roleRef:
  kind: ClusterRole
  name: argocd-microservices-manager
  apiGroup: rbac.authorization.k8s.io
EOF

print_status "Cluster-wide RBAC configured for ArgoCD"

# Create environment validation script
cat > scripts/validate-environments.sh << 'EOF'
#!/bin/bash

ENVIRONMENTS=("dev" "staging" "production")
BASE_NAMESPACE="microservices"

echo "🔍 Validating environment setup..."
echo "=================================="

for env in "${ENVIRONMENTS[@]}"; do
    namespace="${BASE_NAMESPACE}-${env}"
    echo ""
    echo "Environment: $env ($namespace)"
    echo "----------------------------"
    
    # Check namespace
    if kubectl get namespace $namespace &> /dev/null; then
        echo "✅ Namespace exists"
    else
        echo "❌ Namespace missing"
        continue
    fi
    
    # Check resource quota
    if kubectl get resourcequota ${env}-resource-quota -n $namespace &> /dev/null; then
        echo "✅ Resource quota configured"
    else
        echo "❌ Resource quota missing"
    fi
    
    # Check limit range
    if kubectl get limitrange ${env}-limit-range -n $namespace &> /dev/null; then
        echo "✅ Limit range configured"
    else
        echo "❌ Limit range missing"
    fi
    
    # Check network policy
    if kubectl get networkpolicy ${env}-network-policy -n $namespace &> /dev/null; then
        echo "✅ Network policy configured"
    else
        echo "❌ Network policy missing"
    fi
    
    # Check service account
    if kubectl get serviceaccount argocd-${env} -n $namespace &> /dev/null; then
        echo "✅ Service account configured"
    else
        echo "❌ Service account missing"
    fi
    
    # Check ConfigMap
    if kubectl get configmap ${env}-config -n $namespace &> /dev/null; then
        echo "✅ Environment ConfigMap exists"
    else
        echo "❌ Environment ConfigMap missing"
    fi
    
    # Check Secret
    if kubectl get secret ${env}-secrets -n $namespace &> /dev/null; then
        echo "✅ Environment Secret exists"
    else
        echo "❌ Environment Secret missing"
    fi
done

echo ""
echo "🔍 Checking ArgoCD RBAC..."
if kubectl get clusterrole argocd-microservices-manager &> /dev/null; then
    echo "✅ ArgoCD cluster role configured"
else
    echo "❌ ArgoCD cluster role missing"
fi

if kubectl get clusterrolebinding argocd-microservices-manager &> /dev/null; then
    echo "✅ ArgoCD cluster role binding configured"
else
    echo "❌ ArgoCD cluster role binding missing"
fi

echo ""
echo "🎉 Environment validation completed!"
EOF

chmod +x scripts/validate-environments.sh

print_status "Environment validation script created"

# Create environment cleanup script
cat > scripts/cleanup-environments.sh << 'EOF'
#!/bin/bash

ENVIRONMENTS=("dev" "staging" "production")
BASE_NAMESPACE="microservices"

echo "🧹 Cleaning up environment namespaces..."
echo "========================================"

read -p "Are you sure you want to delete all environment namespaces? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 1
fi

for env in "${ENVIRONMENTS[@]}"; do
    namespace="${BASE_NAMESPACE}-${env}"
    echo "Deleting $namespace..."
    kubectl delete namespace $namespace --ignore-not-found=true
done

echo "Deleting monitoring namespace..."
kubectl delete namespace monitoring --ignore-not-found=true

echo "Deleting cluster-wide RBAC..."
kubectl delete clusterrole argocd-microservices-manager --ignore-not-found=true
kubectl delete clusterrolebinding argocd-microservices-manager --ignore-not-found=true

echo "🎉 Cleanup completed!"
EOF

chmod +x scripts/cleanup-environments.sh

print_status "Environment cleanup script created"

# Update environment configuration file
cat >> .env.minikube << EOF

# Environment Configuration
ENVIRONMENTS="dev staging production"
BASE_NAMESPACE=$BASE_NAMESPACE
DEV_NAMESPACE=${BASE_NAMESPACE}-dev
STAGING_NAMESPACE=${BASE_NAMESPACE}-staging
PRODUCTION_NAMESPACE=${BASE_NAMESPACE}-production
MONITORING_NAMESPACE=monitoring
EOF

print_status "Environment configuration saved to .env.minikube"

# Display summary
echo ""
echo -e "${GREEN}🎉 Environment setup completed successfully!${NC}"
echo ""
echo -e "${BLUE}Created Environments:${NC}"
echo "===================="
for env in "${ENVIRONMENTS[@]}"; do
    namespace="${BASE_NAMESPACE}-${env}"
    echo "• $env: $namespace"
done
echo "• monitoring: monitoring"
echo ""
echo -e "${BLUE}Each environment includes:${NC}"
echo "========================="
echo "• Dedicated namespace with labels"
echo "• Resource quotas and limits"
echo "• Network policies for isolation"
echo "• Service accounts and RBAC"
echo "• Environment-specific ConfigMaps"
echo "• Secret templates"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "==========="
echo "1. Validate setup: ./scripts/validate-environments.sh"
echo "2. Update Kustomize overlays for ArgoCD compatibility"
echo "3. Create ArgoCD applications for each environment"
echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo "• kubectl get namespaces                    - List all namespaces"
echo "• kubectl get all -n microservices-dev     - Check dev environment"
echo "• ./scripts/validate-environments.sh       - Validate all environments"
echo "• ./scripts/cleanup-environments.sh        - Clean up all environments"