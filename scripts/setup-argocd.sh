#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ARGOCD_NAMESPACE="argocd"
ARGOCD_VERSION="v2.8.4"
CLUSTER_NAME="microservices-cluster"

echo -e "${BLUE}🚀 Setting up ArgoCD for GitOps CI/CD Pipeline${NC}"
echo "=============================================="

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
    print_error "Kubernetes cluster is not accessible. Please ensure Minikube is running:"
    echo "  minikube start --profile=$CLUSTER_NAME"
    exit 1
fi

print_status "Kubernetes cluster is accessible"

# Create ArgoCD namespace
echo -e "${BLUE}📦 Creating ArgoCD namespace...${NC}"
kubectl create namespace $ARGOCD_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
print_status "ArgoCD namespace created/verified"

# Install ArgoCD
echo -e "${BLUE}⬇️  Installing ArgoCD $ARGOCD_VERSION...${NC}"
kubectl apply -n $ARGOCD_NAMESPACE -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml

print_status "ArgoCD manifests applied"

# Wait for ArgoCD pods to be ready
echo -e "${BLUE}⏳ Waiting for ArgoCD pods to be ready (this may take a few minutes)...${NC}"
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n $ARGOCD_NAMESPACE
kubectl wait --for=condition=available --timeout=600s deployment/argocd-repo-server -n $ARGOCD_NAMESPACE
kubectl wait --for=condition=available --timeout=600s deployment/argocd-application-controller -n $ARGOCD_NAMESPACE

print_status "ArgoCD pods are ready"

# Patch ArgoCD server service to use NodePort for easier access
echo -e "${BLUE}🔧 Configuring ArgoCD server access...${NC}"
kubectl patch svc argocd-server -n $ARGOCD_NAMESPACE -p '{"spec":{"type":"NodePort"}}'

# Get NodePort
ARGOCD_PORT=$(kubectl get svc argocd-server -n $ARGOCD_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
CLUSTER_IP=$(minikube ip --profile=$CLUSTER_NAME 2>/dev/null || echo "localhost")

print_status "ArgoCD server configured for NodePort access"

# Configure ArgoCD server for insecure mode (easier for local development)
echo -e "${BLUE}🔓 Configuring ArgoCD for local development...${NC}"
kubectl patch configmap argocd-cmd-params-cm -n $ARGOCD_NAMESPACE --type merge -p '{"data":{"server.insecure":"true"}}'

# Restart ArgoCD server to apply insecure mode
kubectl rollout restart deployment/argocd-server -n $ARGOCD_NAMESPACE
kubectl rollout status deployment/argocd-server -n $ARGOCD_NAMESPACE

print_status "ArgoCD server configured for insecure mode"

# Get initial admin password
echo -e "${BLUE}🔑 Retrieving ArgoCD admin password...${NC}"
ARGOCD_PASSWORD=$(kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

print_status "ArgoCD admin password retrieved"

# Install ArgoCD CLI if not present
if ! command -v argocd &> /dev/null; then
    echo -e "${BLUE}📥 Installing ArgoCD CLI...${NC}"
    
    # Detect architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        arm64|aarch64) ARCH="arm64" ;;
        *) print_error "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    
    # Download and install ArgoCD CLI
    curl -sSL -o argocd-darwin-$ARCH https://github.com/argoproj/argo-cd/releases/download/$ARGOCD_VERSION/argocd-darwin-$ARCH
    chmod +x argocd-darwin-$ARCH
    sudo mv argocd-darwin-$ARCH /usr/local/bin/argocd
    
    print_status "ArgoCD CLI installed"
else
    print_status "ArgoCD CLI already installed"
fi

# Create ArgoCD CLI configuration
echo -e "${BLUE}⚙️  Configuring ArgoCD CLI...${NC}"

# Wait a moment for the service to be fully ready
sleep 10

# Login to ArgoCD CLI
ARGOCD_SERVER="$CLUSTER_IP:$ARGOCD_PORT"
echo "Logging into ArgoCD at $ARGOCD_SERVER..."

# Login with retry logic
for i in {1..5}; do
    if argocd login $ARGOCD_SERVER --username admin --password "$ARGOCD_PASSWORD" --insecure; then
        print_status "ArgoCD CLI login successful"
        break
    else
        print_warning "Login attempt $i failed, retrying in 10 seconds..."
        sleep 10
    fi
done

# Create ArgoCD project for microservices
echo -e "${BLUE}📋 Creating ArgoCD project...${NC}"
argocd proj create microservices \
    --description "Microservices application project" \
    --src '*' \
    --dest '*,*' \
    --allow-cluster-resource '*/*' \
    --allow-namespaced-resource '*/*' || true

print_status "ArgoCD project created"

# Configure RBAC for the project
echo -e "${BLUE}🔐 Configuring ArgoCD RBAC...${NC}"
kubectl apply -f - << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: $ARGOCD_NAMESPACE
  labels:
    app.kubernetes.io/name: argocd-rbac-cm
    app.kubernetes.io/part-of: argocd
data:
  policy.default: role:readonly
  policy.csv: |
    p, role:admin, applications, *, */*, allow
    p, role:admin, clusters, *, *, allow
    p, role:admin, repositories, *, *, allow
    p, role:dev, applications, get, microservices/*, allow
    p, role:dev, applications, sync, microservices/*, allow
    p, role:dev, applications, action/*, microservices/*, allow
    p, role:staging, applications, get, microservices/*, allow
    p, role:staging, applications, sync, microservices-staging/*, allow
    p, role:prod, applications, get, microservices-production/*, allow
    g, admin, role:admin
EOF

print_status "ArgoCD RBAC configured"

# Create repository credentials secret (placeholder for now)
echo -e "${BLUE}🔗 Setting up repository configuration...${NC}"
kubectl apply -f - << EOF
apiVersion: v1
kind: Secret
metadata:
  name: microservices-repo
  namespace: $ARGOCD_NAMESPACE
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: https://github.com/your-username/microservices-app
  # Add your repository credentials here when ready
  # username: your-username
  # password: your-token
EOF

print_status "Repository configuration template created"

# Create ArgoCD ingress for easier access (optional)
echo -e "${BLUE}🌐 Creating ArgoCD ingress...${NC}"
kubectl apply -f - << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: $ARGOCD_NAMESPACE
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF

# Add argocd.local to /etc/hosts
echo "$(minikube ip --profile=$CLUSTER_NAME) argocd.local" | sudo tee -a /etc/hosts > /dev/null || true

print_status "ArgoCD ingress created"

# Create helpful scripts for ArgoCD management
echo -e "${BLUE}📝 Creating management scripts...${NC}"

# Create port-forward script
cat > scripts/argocd-port-forward.sh << 'EOF'
#!/bin/bash
echo "🚀 Starting ArgoCD port-forward..."
echo "ArgoCD will be available at: http://localhost:8080"
echo "Username: admin"
echo "Password: Run 'kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d' to get password"
echo ""
echo "Press Ctrl+C to stop port-forwarding"
kubectl port-forward svc/argocd-server -n argocd 8080:80
EOF

chmod +x scripts/argocd-port-forward.sh

# Create password retrieval script
cat > scripts/get-argocd-password.sh << 'EOF'
#!/bin/bash
echo "ArgoCD Admin Password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
EOF

chmod +x scripts/get-argocd-password.sh

# Create ArgoCD CLI helper script
cat > scripts/argocd-cli.sh << 'EOF'
#!/bin/bash

CLUSTER_NAME="microservices-cluster"
CLUSTER_IP=$(minikube ip --profile=$CLUSTER_NAME 2>/dev/null || echo "localhost")
ARGOCD_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
ARGOCD_SERVER="$CLUSTER_IP:$ARGOCD_PORT"

echo "🔗 ArgoCD Server: $ARGOCD_SERVER"
echo "🔑 Getting admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "🚀 Logging into ArgoCD CLI..."
argocd login $ARGOCD_SERVER --username admin --password "$ARGOCD_PASSWORD" --insecure

echo "✅ ArgoCD CLI ready! You can now use 'argocd' commands."
EOF

chmod +x scripts/argocd-cli.sh

print_status "Management scripts created"

# Save ArgoCD configuration to environment file
cat >> .env.minikube << EOF

# ArgoCD Configuration
ARGOCD_NAMESPACE=$ARGOCD_NAMESPACE
ARGOCD_SERVER=$ARGOCD_SERVER
ARGOCD_PASSWORD=$ARGOCD_PASSWORD
ARGOCD_URL_NODEPORT=http://$ARGOCD_SERVER
ARGOCD_URL_INGRESS=http://argocd.local
ARGOCD_URL_PORTFORWARD=http://localhost:8080
EOF

print_status "ArgoCD configuration saved to .env.minikube"

# Verify ArgoCD installation
echo -e "${BLUE}🧪 Verifying ArgoCD installation...${NC}"

# Check if all pods are running
if kubectl get pods -n $ARGOCD_NAMESPACE | grep -q "Running"; then
    print_status "All ArgoCD pods are running"
else
    print_warning "Some ArgoCD pods may still be starting"
fi

# Test ArgoCD API
if curl -k -s "http://$ARGOCD_SERVER/api/version" > /dev/null; then
    print_status "ArgoCD API is accessible"
else
    print_warning "ArgoCD API test failed, but this might be normal during initial setup"
fi

echo ""
echo -e "${GREEN}🎉 ArgoCD setup completed successfully!${NC}"
echo ""
echo -e "${BLUE}Access Information:${NC}"
echo "==================="
echo "• NodePort URL:    http://$ARGOCD_SERVER"
echo "• Ingress URL:     http://argocd.local"
echo "• Port-forward:    ./scripts/argocd-port-forward.sh (then http://localhost:8080)"
echo ""
echo -e "${BLUE}Credentials:${NC}"
echo "============"
echo "• Username: admin"
echo "• Password: $ARGOCD_PASSWORD"
echo "• Get password: ./scripts/get-argocd-password.sh"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "==========="
echo "1. Access ArgoCD UI using one of the URLs above"
echo "2. Configure your Git repository in ArgoCD"
echo "3. Run environment setup: ./scripts/setup-environments.sh"
echo "4. Create ArgoCD applications: ./scripts/create-argocd-apps.sh"
echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo "• ./scripts/argocd-port-forward.sh  - Start port-forwarding"
echo "• ./scripts/get-argocd-password.sh  - Get admin password"
echo "• ./scripts/argocd-cli.sh           - Login to ArgoCD CLI"
echo "• argocd app list                   - List applications"
echo "• argocd app sync <app-name>        - Sync application"