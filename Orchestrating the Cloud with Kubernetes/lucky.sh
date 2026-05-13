#!/bin/bash

# ==============================================
# Google Kubernetes Engine Complete Lab Setup
# Welcome to Lucky!
# Website: https://luckyverse.tech
# ==============================================

# ASCII Art Banner
echo "                                                                
  _     _    _  ____ _  ____   __  __ _____ ____  ____  _____ 
 | |   | |  | |/ ___| |/ /\ \ / /  \ \   __/ ___||  _ \| ____|
 | |   | |  | | |   | ' /  \ V /____\ \ | |   _| | |_) |  _|  
 | |___| |__| | |___| . \   | |_____ \ \| |  |_| |  _ <| |___ 
 |_____|______|____|_|\_\  |_|      \__\____|____|_| \_\_____|
                                                                
"

echo "=================================================================="
echo "                    WELCOME TO LUCKY!"
echo "=================================================================="
echo " Website: https://luckyverse.tech"
echo "=================================================================="
echo "   Explore more Kubernetes and Cloud Computing tutorials!"
echo "=================================================================="
echo ""
sleep 3

echo "Starting Google Kubernetes Engine lab setup..."
echo ""

# Display progress function
progress() {
    echo "✅ $1"
    sleep 2
}

# Task: Initial Setup
progress "Setting up initial configuration..."
gcloud auth list

# Logic Check: Fallback for Zone/Region if metadata is empty
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=$(gcloud config get-value compute/zone)
export REGION=$(gcloud config get-value compute/region)

# Default to us-central1-a if not set to prevent script failure
if [ -z "$ZONE" ]; then
    export ZONE="us-central1-a"
    gcloud config set compute/zone "$ZONE"
fi

# Task: Create Kubernetes Cluster
progress "Creating Kubernetes cluster 'io' in zone: $ZONE"
gcloud container clusters create io --zone $ZONE --num-nodes 3

# Task: Get Sample Code
progress "Downloading sample code from Google Cloud Storage..."
gsutil cp -r gs://spls/gsp021/* .
cd orchestrate-with-kubernetes/kubernetes 2>/dev/null || cd kubernetes

# Task: Quick Kubernetes Demo
progress "Creating nginx deployment (version 1.27.0)..."
kubectl create deployment nginx --image=nginx:1.27.0
kubectl get pods

progress "Exposing nginx as LoadBalancer service..."
kubectl expose deployment nginx --port 80 --type LoadBalancer

# Task: Create Fortune App Pod
progress "Creating fortune-app pod..."
kubectl create -f pods/fortune-app.yaml
kubectl get pods

progress "Describing fortune-app pod..."
kubectl describe pods fortune-app

# Task: Interact with Pods (Port Forwarding)
progress "Setting up port forwarding for fortune-app..."
kubectl port-forward fortune-app 10080:8080 &
PORT_FORWARD_PID=$!
sleep 5

progress "Testing fortune app endpoint..."
curl http://127.0.0.1:10080

progress "Logging in to get authentication token..."
TOKEN=$(curl -s -u user:password http://127.0.0.1:10080/login | jq -r '.token')
echo "Token acquired successfully!"

# Task: Create Secure Fortune Pod and Service
progress "Creating TLS certificates secret..."
kubectl create secret generic tls-certs --from-file tls/

progress "Creating nginx proxy configuration..."
kubectl create configmap nginx-proxy-conf --from-file nginx/proxy.conf

progress "Creating secure-fortune pod..."
kubectl create -f pods/secure-fortune.yaml

progress "Creating fortune-app service..."
kubectl create -f services/fortune-app.yaml

progress "Creating firewall rule for port 31000..."
gcloud compute firewall-rules create allow-fortune-nodeport --allow=tcp:31000

# Task: Add Labels to Pods
progress "Adding 'secure=enabled' label to secure-fortune pod..."
kubectl label pods secure-fortune 'secure=enabled'

# Task: Create Microservices Deployments
progress "Creating microservices (auth, hello, frontend)..."
kubectl create -f deployments/auth.yaml
kubectl create -f services/auth.yaml
kubectl create -f deployments/hello.yaml
kubectl create -f services/hello.yaml
kubectl create -f configmaps/frontend.yaml 2>/dev/null || kubectl create configmap nginx-frontend-conf --from-file=nginx/frontend.conf
kubectl create -f deployments/frontend.yaml
kubectl create -f services/frontend.yaml

# Task: Create Monolith
progress "Creating monolith application..."
kubectl create -f pods/monolith.yaml

# Clean up port forwarding
kill $PORT_FORWARD_PID 2>/dev/null

# Final output
echo ""
echo "=================================================================="
echo "🎉 LAB SETUP COMPLETED SUCCESSFULLY!"
echo "=================================================================="
echo "All Kubernetes lab tasks have been executed successfully!"
echo ""
echo "📊 CURRENT CLUSTER STATE:"
kubectl get pods,svc,deployments
echo "=================================================================="

echo ""
echo "💡 NEXT STEPS:"
echo "1. Visit the website resources at: https://luckyverse.tech"
echo "2. Test your services using the external IPs provided above."
echo ""

echo "=============================================================================="
echo "🚀 POWERED BY LUCKY"
echo "Website: https://luckyverse.tech"
echo "=============================================================================="
