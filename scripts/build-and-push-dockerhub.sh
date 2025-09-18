#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration - UPDATE THESE VALUES
DOCKER_USERNAME="${DOCKER_USERNAME:-your-dockerhub-username}"  # Set your Docker Hub username
REGISTRY_URL="docker.io"  # Docker Hub registry

echo -e "${BLUE}🐳 Building and pushing images to Docker Hub${NC}"

# Check if Docker username is set
if [ "$DOCKER_USERNAME" = "salilkayastha" ]; then
    echo -e "${RED}❌ Please set your Docker Hub username:${NC}"
    echo "export DOCKER_USERNAME=your-actual-username"
    echo "Or edit this script and replace 'your-dockerhub-username'"
    exit 1
fi

# Generate image tag
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
COMMIT_SHA=$(git rev-parse --short HEAD)
IMAGE_TAG="${BRANCH_NAME}-${COMMIT_SHA}"

echo "Docker Hub Username: $DOCKER_USERNAME"
echo "Image tag: $IMAGE_TAG"
echo "=================================================="

# Check if logged in to Docker Hub
echo -e "${BLUE}🔐 Checking Docker Hub authentication...${NC}"
if ! docker info | grep -q "Username: $DOCKER_USERNAME"; then
    echo -e "${YELLOW}⚠️  Please login to Docker Hub:${NC}"
    echo "docker login"
    exit 1
fi

echo -e "${GREEN}✅ Authenticated with Docker Hub${NC}"

# Build and push images
echo -e "${BLUE}🏗️  Building API service...${NC}"
docker build -t $DOCKER_USERNAME/api-service:$IMAGE_TAG ./api-service
docker build -t $DOCKER_USERNAME/api-service:latest ./api-service
docker push $DOCKER_USERNAME/api-service:$IMAGE_TAG
docker push $DOCKER_USERNAME/api-service:latest
echo -e "${GREEN}✅ API service pushed${NC}"

echo -e "${BLUE}🏗️  Building Frontend service...${NC}"
docker build -t $DOCKER_USERNAME/frontend-service:$IMAGE_TAG ./frontend-service
docker build -t $DOCKER_USERNAME/frontend-service:latest ./frontend-service
docker push $DOCKER_USERNAME/frontend-service:$IMAGE_TAG
docker push $DOCKER_USERNAME/frontend-service:latest
echo -e "${GREEN}✅ Frontend service pushed${NC}"

echo -e "${BLUE}🏗️  Building Worker service...${NC}"
docker build -t $DOCKER_USERNAME/worker-service:$IMAGE_TAG ./worker-service
docker build -t $DOCKER_USERNAME/worker-service:latest ./worker-service
docker push $DOCKER_USERNAME/worker-service:$IMAGE_TAG
docker push $DOCKER_USERNAME/worker-service:latest
echo -e "${GREEN}✅ Worker service pushed${NC}"

# Determine environment based on branch
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

# Update images using kustomize
kustomize edit set image api-service=$DOCKER_USERNAME/api-service:$IMAGE_TAG
kustomize edit set image frontend-service=$DOCKER_USERNAME/frontend-service:$IMAGE_TAG
kustomize edit set image worker-service=$DOCKER_USERNAME/worker-service:$IMAGE_TAG

cd ../../..

echo -e "${GREEN}🎉 Build and push completed successfully!${NC}"
echo ""
echo -e "${BLUE}Images pushed to Docker Hub:${NC}"
echo "• $DOCKER_USERNAME/api-service:$IMAGE_TAG"
echo "• $DOCKER_USERNAME/frontend-service:$IMAGE_TAG"
echo "• $DOCKER_USERNAME/worker-service:$IMAGE_TAG"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. git add k8s/overlays/$ENV/"
echo "2. git commit -m 'Update image tags to $IMAGE_TAG'"
echo "3. git push"
echo "4. Check ArgoCD: https://localhost:8080"
echo "5. Monitor deployment: kubectl get pods -n microservices-$ENV"