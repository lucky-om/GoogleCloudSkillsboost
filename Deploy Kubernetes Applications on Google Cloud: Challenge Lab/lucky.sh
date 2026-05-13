#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ---------- Color variables ----------
BLACK=`tput setaf 0 2>/dev/null || echo ''`
RED=`tput setaf 1 2>/dev/null || echo ''`
GREEN=`tput setaf 2 2>/dev/null || echo ''`
YELLOW=`tput setaf 3 2>/dev/null || echo ''`
BLUE=`tput setaf 4 2>/dev/null || echo ''`
MAGENTA=`tput setaf 5 2>/dev/null || echo ''`
CYAN=`tput setaf 6 2>/dev/null || echo ''`
WHITE=`tput setaf 7 2>/dev/null || echo ''`

BG_BLACK=`tput setab 0 2>/dev/null || echo ''`
BG_RED=`tput setab 1 2>/dev/null || echo ''`
BG_GREEN=`tput setab 2 2>/dev/null || echo ''`
BG_YELLOW=`tput setab 3 2>/dev/null || echo ''`
BG_BLUE=`tput setab 4 2>/dev/null || echo ''`
BG_MAGENTA=`tput setab 5 2>/dev/null || echo ''`
BG_CYAN=`tput setab 6 2>/dev/null || echo ''`
BG_WHITE=`tput setab 7 2>/dev/null || echo ''`

BOLD=`tput bold 2>/dev/null || echo ''`
RESET=`tput sgr0 2>/dev/null || echo ''`

# Array of color codes excluding black and white
TEXT_COLORS=($RED $GREEN $YELLOW $BLUE $MAGENTA $CYAN)
BG_COLORS=($BG_RED $BG_GREEN $BG_YELLOW $BG_BLUE $BG_MAGENTA $BG_CYAN)

# Pick random colors
RANDOM_TEXT_COLOR=${TEXT_COLORS[$RANDOM % ${#TEXT_COLORS[@]}]}
RANDOM_BG_COLOR=${BG_COLORS[$RANDOM % ${#BG_COLORS[@]}]}

# Random Thank You Messages
THANK_YOU_MESSAGES=(
    "Details received. Proceeding."
    "Inputs recorded."
    "Configuration set."
    "Data logged. Starting build."
)
RANDOM_THANK_YOU=${THANK_YOU_MESSAGES[$RANDOM % ${#THANK_YOU_MESSAGES[@]}]}

#----------------------------------------------------start--------------------------------------------------#

echo "${CYAN}${BOLD}Welcome to Lucky - Cloud Engineering Suite${RESET}"
echo "${RANDOM_BG_COLOR}${RANDOM_TEXT_COLOR}${BOLD}Initializing Setup${RESET}"
echo "${YELLOW}Website: https://luckyverse.tech${RESET}"
echo

# ---------- defaults for the lab ----------
DEFAULT_REPO="valkyrie-docker-repo"
DEFAULT_IMG="valkyrie-dev"
DEFAULT_TAG="v0.0.1"
DEFAULT_REGION="us-west1"
DEFAULT_ZONE="us-west1-b"

# interactive prompt
read -p "Enter Repository Name [${DEFAULT_REPO}]: " REPO
REPO=${REPO:-$DEFAULT_REPO}

read -p "Enter Docker Image name [${DEFAULT_IMG}]: " DCKR_IMG
DCKR_IMG=${DCKR_IMG:-$DEFAULT_IMG}

read -p "Enter Tag [${DEFAULT_TAG}]: " TAG
TAG=${TAG:-$DEFAULT_TAG}

read -p "Enter Region [${DEFAULT_REGION}]: " REGION
REGION=${REGION:-$DEFAULT_REGION}

read -p "Enter Zone [${DEFAULT_ZONE}]: " ZONE
ZONE=${ZONE:-$DEFAULT_ZONE}

echo
echo "${RANDOM_TEXT_COLOR}${BOLD}$RANDOM_THANK_YOU${RESET}"
echo

# ---------- project detection ----------
PROJECT_ID=${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}
if [ -z "$PROJECT_ID" ]; then
  echo "${RED}ERROR: No GCP project found.${RESET}"
  exit 1
fi
echo "${CYAN}Using project: $PROJECT_ID${RESET}"
echo "${CYAN}Zone: $ZONE, Region: $REGION${RESET}"
echo

# ---------- Download & prepare app source ----------
echo "${GREEN}Fetching source files...${RESET}"
if [ ! -f valkyrie-app.tgz ] && [ ! -d valkyrie-app ]; then
  gsutil cp gs://spls/gsp318/valkyrie-app.tgz .
fi

if [ -f valkyrie-app.tgz ] && [ ! -d valkyrie-app ]; then
  tar -xzf valkyrie-app.tgz
fi

if [ ! -d valkyrie-app ]; then
  echo "${RED}ERROR: Source files missing.${RESET}"
  exit 1
fi

cd valkyrie-app

# ---------- Create Dockerfile ----------
echo "${YELLOW}Generating Dockerfile...${RESET}"
cat > Dockerfile <<'EOF'
FROM golang:1.10
WORKDIR /go/src/app
COPY source .
RUN go install -v
ENTRYPOINT ["app","-single=true","-port=8080"]
EOF

# ---------- Build & Push via Cloud Build ----------
IMAGE_PATH="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${DCKR_IMG}:${TAG}"
echo "${BLUE}Target Image Path:${RESET} ${IMAGE_PATH}"

if ! gcloud artifacts repositories describe "$REPO" --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "${YELLOW}Creating Artifact Registry repository...${RESET}"
  gcloud artifacts repositories create "$REPO" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Lucky Valkyrie Repo" \
    --project="$PROJECT_ID"
fi

echo "${BLUE}Configuring Docker auth...${RESET}"
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet || true

echo "${BLUE}Submitting build to Cloud Build...${RESET}"
gcloud builds submit --tag "${IMAGE_PATH}" .

# ---------- Update k8s deployment manifest ----------
if [ -f k8s/deployment.yaml ]; then
  echo "${GREEN}Patching deployment with new image...${RESET}"
  sed -i.bak "s#IMAGE_HERE#${IMAGE_PATH}#g" k8s/deployment.yaml
else
  echo "${RED}ERROR: k8s/deployment.yaml not found.${RESET}"
  exit 1
fi

# ---------- GKE Cluster Management ----------
CLUSTER_NAME="valkyrie-dev"
if ! gcloud container clusters list --project "$PROJECT_ID" --format="value(name)" | grep -q "^${CLUSTER_NAME}$"; then
  echo "${YELLOW}Creating cluster ${CLUSTER_NAME} in zone ${ZONE}...${RESET}"
  gcloud container clusters create "$CLUSTER_NAME" --zone "$ZONE" --num-nodes=1 --project "$PROJECT_ID"
fi

echo "${CYAN}Syncing kubectl credentials...${RESET}"
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$ZONE" --project "$PROJECT_ID"

# ---------- Deployment ----------
echo "${BLUE}Applying manifests to cluster...${RESET}"
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# ---------- Service Monitoring ----------
SERVICE_NAME=$(grep -E "name:\s*" k8s/service.yaml | head -n1 | awk '{print $2}' || true)
if [ -n "$SERVICE_NAME" ]; then
  echo "${CYAN}Waiting for external IP for ${SERVICE_NAME}...${RESET}"
  for i in {1..40}; do
    EX_IP=$(kubectl get svc "$SERVICE_NAME" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [ -n "$EX_IP" ]; then
      echo "${GREEN}External Endpoint: ${EX_IP}${RESET}"
      break
    fi
    echo -n "."
    sleep 5
  done
  echo
fi

echo
echo "${GREEN}${BOLD}Deployment sequence completed successfully.${RESET}"
echo "${CYAN}Live Image: ${IMAGE_PATH}${RESET}"
echo "${YELLOW}For more tools, visit: https://luckyverse.tech${RESET}"
echo
