#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🐳 Building and pushing images to Minikube registry${NC}"

# Generate image tag
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
COMMIT_SHA=$(git rev-parse --short HEAD)
IMAGE_TAG="${BRANCH_NAME}-${COMMIT_SHA}"

echo "Image tag: $IMAGE_TAG"
echo "=================================================="

# Set up port-forward for registry
echo -e "${BLUE}🔧 Setting up registry access...${NC}"
pkill -f "kubectl port-forward.*registry" || true
kubectl port-forward svc/registry 5000:80 -n kube-system > /dev/null 2>&1 &
sleep 3

REGISTRY_URL="localhost:5000"

# Test registry
if curl -s "http://$REGISTRY_URL/v2/" > /dev/null; then
    echo -e "${GREEN}✅ Registry accessible at $REGISTRY_URL${NC}"
else
    echo -e "${YELLOW}⚠️  Registry not accessible, using Minikube Docker daemon${NC}"
    eval $(minikube docker-env --profile=microservices-cluster)
    REGISTRY_URL=""
fi

# Build images
echo -e "${BLUE}🏗️  Building images...${NC}"

docker build -t api-service:$IMAGE_TAG ./api-service
docker build -t frontend-service:$IMAGE_TAG ./frontend-service
docker build -t worker-service:$IMAGE_TAG ./worker-service

if [ -n "$REGISTRY_URL" ]; then
    # Tag and push to registry
    docker tag api-service:$IMAGE_TAG $REGISTRY_URL/api-service:$IMAGE_TAG
    docker tag frontend-service:$IMAGE_TAG $REGISTRY_URL/frontend-service:$IMAGE_TAG
    docker tag worker-service:$IMAGE_TAG $REGISTRY_URL/worker-service:$IMAGE_TAG
    
    docker push $REGISTRY_URL/api-service:$IMAGE_TAG
    docker push $REGISTRY_URL/frontend-service:$IMAGE_TAG
    docker push $REGISTRY_URL/worker-service:$IMAGE_TAG
    
    echo -e "${GREEN}✅ Images pushed to registry${NC}"
else
    echo -e "${GREEN}✅ Images built in Minikube Docker daemon${NC}"
fi

# Determine environment
if [[ "$BRANCH_NAME" == "main" ]]; then
    ENV="production"
elif [[ "$BRANCH_NAME" == "develop" ]]; then
    ENV="staging"
else
    ENV="dev"
fi

echo -e "${BLUE}📝 Updating $ENV environment manifests...${NC}"

# Update Kustomize manifests
cd k8s/overlays/$ENV

if [ -n "$REGISTRY_URL" ]; then
    # Update with registry URLs
    kustomize edit set image api-service=$REGISTRY_URL/api-service:$IMAGE_TAG
    kustomize edit set image frontend-service=$REGISTRY_URL/frontend-service:$IMAGE_TAG
    kustomize edit set image worker-service=$REGISTRY_URL/worker-service:$IMAGE_TAG
else
    # Update with local image names (no registry)
    kustomize edit set image api-service=api-service:$IMAGE_TAG
    kustomize edit set image frontend-service=frontend-service:$IMAGE_TAG
    kustomize edit set image worker-service=worker-service:$IMAGE_TAG
fi

cd ../../..

echo -e "${GREEN}🎉 Build completed!${NC}"
echo ""
echo "Next steps:"
echo "1. git add k8s/overlays/$ENV/"
echo "2. git commit -m 'Update image tags to $IMAGE_TAG'"
echo "3. git push"
echo "4. Check ArgoCD: https://localhost:8080"