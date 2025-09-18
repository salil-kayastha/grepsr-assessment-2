#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if registry service exists and set up access
REGISTRY_SERVICE=$(kubectl get service registry -n kube-system --no-headers 2>/dev/null | wc -l)

if [ "$REGISTRY_SERVICE" -eq 1 ]; then
    echo -e "${BLUE}🔧 Setting up registry access via port-forward...${NC}"
    # Kill any existing port-forward
    pkill -f "kubectl port-forward.*registry" || true
    # Start port-forward in background
    kubectl port-forward svc/registry 5000:80 -n kube-system > /dev/null 2>&1 &
    sleep 3
    REGISTRY_URL="localhost:5000"
    USE_MINIKUBE_DOCKER=false
    echo "Registry accessible at: $REGISTRY_URL"
else
    echo -e "${YELLOW}⚠️  Registry service not found, using Minikube Docker daemon directly${NC}"
    REGISTRY_URL="localhost:5000"
    USE_MINIKUBE_DOCKER=true
fi

# Generate image tag
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
COMMIT_SHA=$(git rev-parse --short HEAD)
IMAGE_TAG="${BRANCH_NAME}-${COMMIT_SHA}"

echo -e "${BLUE}🐳 Building and pushing images to local registry${NC}"
echo "Registry: $REGISTRY_URL"
echo "Image tag: $IMAGE_TAG"
echo "=================================================="

# Function to print status
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Configure Docker to use Minikube's Docker daemon
echo -e "${BLUE}🔧 Configuring Docker to use Minikube's daemon...${NC}"
eval $(minikube docker-env)

# Build and tag images
echo -e "${BLUE}🏗️  Building API service...${NC}"
docker build -t api-service:$IMAGE_TAG ./api-service
docker tag api-service:$IMAGE_TAG $REGISTRY_URL/api-service:$IMAGE_TAG
docker tag api-service:$IMAGE_TAG $REGISTRY_URL/api-service:latest
print_status "API service built and tagged"

echo -e "${BLUE}🏗️  Building Frontend service...${NC}"
docker build -t frontend-service:$IMAGE_TAG ./frontend-service
docker tag frontend-service:$IMAGE_TAG $REGISTRY_URL/frontend-service:$IMAGE_TAG
docker tag frontend-service:$IMAGE_TAG $REGISTRY_URL/frontend-service:latest
print_status "Frontend service built and tagged"

echo -e "${BLUE}🏗️  Building Worker service...${NC}"
docker build -t worker-service:$IMAGE_TAG ./worker-service
docker tag worker-service:$IMAGE_TAG $REGISTRY_URL/worker-service:$IMAGE_TAG
docker tag worker-service:$IMAGE_TAG $REGISTRY_URL/worker-service:latest
print_status "Worker service built and tagged"

# Push images to registry (if external registry is available)
if [ "$USE_MINIKUBE_DOCKER" = "false" ]; then
    echo -e "${BLUE}📤 Pushing images to registry...${NC}"
    
    docker push $REGISTRY_URL/api-service:$IMAGE_TAG
    docker push $REGISTRY_URL/api-service:latest
    print_status "API service pushed"
    
    docker push $REGISTRY_URL/frontend-service:$IMAGE_TAG
    docker push $REGISTRY_URL/frontend-service:latest
    print_status "Frontend service pushed"
    
    docker push $REGISTRY_URL/worker-service:$IMAGE_TAG
    docker push $REGISTRY_URL/worker-service:latest
    print_status "Worker service pushed"
else
    echo -e "${BLUE}📦 Images built in Minikube Docker daemon (no push needed)${NC}"
    print_status "Images available in Minikube Docker daemon"
fi

# Update Kustomize manifests
echo -e "${BLUE}📝 Updating Kustomize manifests...${NC}"

# Determine environment based on branch
if [[ "$BRANCH_NAME" == "main" ]]; then
    ENV="production"
elif [[ "$BRANCH_NAME" == "develop" ]]; then
    ENV="staging"
else
    ENV="dev"
fi

echo "Updating $ENV environment with image tag: $IMAGE_TAG"

# Check if kustomize is installed
if ! command -v kustomize &> /dev/null; then
    echo -e "${YELLOW}⚠️  Installing kustomize...${NC}"
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    sudo mv kustomize /usr/local/bin/
fi

# Update image tags in the appropriate overlay
cd k8s/overlays/$ENV

# Update images using kustomize
kustomize edit set image api-service=$REGISTRY_URL/api-service:$IMAGE_TAG
kustomize edit set image frontend-service=$REGISTRY_URL/frontend-service:$IMAGE_TAG
kustomize edit set image worker-service=$REGISTRY_URL/worker-service:$IMAGE_TAG

print_status "Kustomize manifests updated for $ENV environment"

# Go back to root directory
cd ../../..

# Verify the changes
echo -e "${BLUE}🔍 Verifying manifest changes...${NC}"
echo "Updated kustomization.yaml for $ENV:"
cat k8s/overlays/$ENV/kustomization.yaml

echo ""
echo -e "${GREEN}🎉 Build and push completed successfully!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Commit the manifest changes: git add k8s/overlays/$ENV/ && git commit -m 'Update image tags to $IMAGE_TAG'"
echo "2. Push to trigger ArgoCD sync: git push"
echo "3. Check ArgoCD UI: https://localhost:8080"
echo "4. Monitor deployment: kubectl get pods -n microservices-$ENV"
echo ""
echo -e "${BLUE}Registry Information:${NC}"
echo "• Registry URL: $REGISTRY_URL"
echo "• Images pushed:"
echo "  - $REGISTRY_URL/api-service:$IMAGE_TAG"
echo "  - $REGISTRY_URL/frontend-service:$IMAGE_TAG"
echo "  - $REGISTRY_URL/worker-service:$IMAGE_TAG"