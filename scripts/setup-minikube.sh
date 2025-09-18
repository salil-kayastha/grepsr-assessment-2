#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="microservices-cluster"
MEMORY="6144"
CPUS="4"
DISK_SIZE="10g"
KUBERNETES_VERSION="v1.28.3"

echo -e "${BLUE}🚀 Setting up Minikube for ArgoCD CI/CD Pipeline${NC}"
echo "=================================================="

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

# Check if Minikube is installed
if ! command -v minikube &> /dev/null; then
    print_error "Minikube is not installed. Please install it first:"
    echo "  brew install minikube"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_warning "kubectl is not installed. Installing via brew..."
    brew install kubectl
fi

print_status "Minikube version: $(minikube version --short)"

# Stop existing cluster if running
if minikube status --profile=$CLUSTER_NAME &> /dev/null; then
    print_warning "Stopping existing Minikube cluster..."
    minikube stop --profile=$CLUSTER_NAME
fi

# Delete existing cluster if it exists
if minikube profile list | grep -q $CLUSTER_NAME; then
    print_warning "Deleting existing cluster to ensure clean setup..."
    minikube delete --profile=$CLUSTER_NAME
fi

echo -e "${BLUE}🔧 Starting Minikube cluster with optimized settings...${NC}"

# Start Minikube with proper configuration
minikube start \
    --profile=$CLUSTER_NAME \
    --memory=$MEMORY \
    --cpus=$CPUS \
    --disk-size=$DISK_SIZE \
    --kubernetes-version=$KUBERNETES_VERSION \
    --driver=docker \
    --container-runtime=docker \
    --feature-gates="EphemeralContainers=true" \
    --extra-config=apiserver.enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,NodeRestriction,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,ResourceQuota

print_status "Minikube cluster started successfully"

# Set kubectl context
kubectl config use-context $CLUSTER_NAME
print_status "kubectl context set to $CLUSTER_NAME"

# Enable required addons
echo -e "${BLUE}🔌 Enabling required addons...${NC}"

addons=(
    "ingress"
    "ingress-dns"
    "registry"
    "metrics-server"
    "storage-provisioner"
    "default-storageclass"
)

for addon in "${addons[@]}"; do
    echo "Enabling $addon..."
    minikube addons enable $addon --profile=$CLUSTER_NAME
    print_status "$addon enabled"
done

# Wait for ingress controller to be ready
echo -e "${BLUE}⏳ Waiting for ingress controller to be ready...${NC}"
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

print_status "Ingress controller is ready"

# Configure local registry
echo -e "${BLUE}🐳 Configuring local Docker registry...${NC}"

# Get registry port
REGISTRY_PORT=$(kubectl get service registry -n kube-system -o jsonpath='{.spec.ports[0].nodePort}')
REGISTRY_IP=$(minikube ip --profile=$CLUSTER_NAME)

print_status "Local registry available at $REGISTRY_IP:$REGISTRY_PORT"

# Create registry alias for easier access
echo "127.0.0.1 registry.local" | sudo tee -a /etc/hosts > /dev/null || true

# Configure Docker to use insecure registry
DOCKER_CONFIG_DIR="$HOME/.docker"
DOCKER_DAEMON_CONFIG="$DOCKER_CONFIG_DIR/daemon.json"

mkdir -p "$DOCKER_CONFIG_DIR"

if [ -f "$DOCKER_DAEMON_CONFIG" ]; then
    # Backup existing config
    cp "$DOCKER_DAEMON_CONFIG" "$DOCKER_DAEMON_CONFIG.backup"
fi

# Create or update daemon.json
cat > "$DOCKER_DAEMON_CONFIG" << EOF
{
  "insecure-registries": [
    "$REGISTRY_IP:$REGISTRY_PORT",
    "registry.local:$REGISTRY_PORT",
    "localhost:5000"
  ]
}
EOF

print_status "Docker daemon configured for insecure registry"

# Test registry connectivity
echo -e "${BLUE}🧪 Testing registry connectivity...${NC}"
if curl -s "http://$REGISTRY_IP:$REGISTRY_PORT/v2/" > /dev/null; then
    print_status "Registry is accessible"
else
    print_warning "Registry test failed, but this might be normal during initial setup"
fi

# Create storage class for persistent volumes
echo -e "${BLUE}💾 Setting up storage configuration...${NC}"
kubectl apply -f - << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: k8s.io/minikube-hostpath
parameters:
  type: pd-ssd
allowVolumeExpansion: true
volumeBindingMode: Immediate
EOF

print_status "Storage class configured"

# Create cluster-admin service account for ArgoCD
echo -e "${BLUE}🔐 Creating service accounts...${NC}"
kubectl apply -f - << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-admin
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: argocd-admin
  namespace: kube-system
EOF

print_status "Service accounts created"

# Verify cluster health
echo -e "${BLUE}🏥 Verifying cluster health...${NC}"

# Check node status
if kubectl get nodes | grep -q "Ready"; then
    print_status "Cluster nodes are ready"
else
    print_error "Cluster nodes are not ready"
    exit 1
fi

# Check system pods
if kubectl get pods -n kube-system | grep -q "Running"; then
    print_status "System pods are running"
else
    print_warning "Some system pods may still be starting"
fi

# Display cluster information
echo -e "${BLUE}📊 Cluster Information${NC}"
echo "======================"
echo "Cluster Name: $CLUSTER_NAME"
echo "Kubernetes Version: $(kubectl version --short --client)"
echo "Cluster IP: $(minikube ip --profile=$CLUSTER_NAME)"
echo "Registry: $REGISTRY_IP:$REGISTRY_PORT"
echo "Dashboard: minikube dashboard --profile=$CLUSTER_NAME"

# Create helpful aliases
echo -e "${BLUE}🔧 Creating helpful aliases...${NC}"
cat >> ~/.zshrc << 'EOF'

# Minikube aliases for microservices project
alias mk='minikube --profile=microservices-cluster'
alias mkstart='minikube start --profile=microservices-cluster'
alias mkstop='minikube stop --profile=microservices-cluster'
alias mkdash='minikube dashboard --profile=microservices-cluster'
alias mkip='minikube ip --profile=microservices-cluster'
alias mkreg='echo "Registry: $(minikube ip --profile=microservices-cluster):$(kubectl get service registry -n kube-system -o jsonpath="{.spec.ports[0].nodePort}")"'

EOF

# Create environment file for easy access to cluster info
cat > .env.minikube << EOF
# Minikube Cluster Configuration
CLUSTER_NAME=$CLUSTER_NAME
CLUSTER_IP=$(minikube ip --profile=$CLUSTER_NAME)
REGISTRY_IP=$REGISTRY_IP
REGISTRY_PORT=$REGISTRY_PORT
REGISTRY_URL=$REGISTRY_IP:$REGISTRY_PORT
KUBECONFIG=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
EOF

print_status "Environment configuration saved to .env.minikube"

echo ""
echo -e "${GREEN}🎉 Minikube setup completed successfully!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Source your shell: source ~/.zshrc"
echo "2. Test the setup: kubectl get nodes"
echo "3. Access dashboard: minikube dashboard --profile=$CLUSTER_NAME"
echo "4. Run ArgoCD installation: ./scripts/setup-argocd.sh"
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo "• mk status          - Check cluster status"
echo "• mkstart           - Start the cluster"
echo "• mkstop            - Stop the cluster"
echo "• mkdash            - Open dashboard"
echo "• mkreg             - Show registry URL"
echo ""
echo -e "${BLUE}Registry Information:${NC}"
echo "• Registry URL: $REGISTRY_IP:$REGISTRY_PORT"
echo "• To push images: docker tag <image> $REGISTRY_IP:$REGISTRY_PORT/<image>"
echo "• Then: docker push $REGISTRY_IP:$REGISTRY_PORT/<image>"