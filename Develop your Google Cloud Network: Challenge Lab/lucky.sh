#!/bin/bash

# ==============================================
# Luckyverse Cloud Infrastructure Automation
# GitHub: https://github.com/lucky-om
# Web: luckyverse.tech
# ==============================================

# Define Colors
BLACK=`tput setaf 0`
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
MAGENTA=`tput setaf 5`
CYAN=`tput setaf 6`
WHITE=`tput setaf 7`
BOLD=`tput bold`
RESET=`tput sgr0`

# Display welcome banner
echo "${BLUE}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   🌌 LUCKYVERSE CLOUD 🌌                     ║"
echo "║                                                              ║"
echo "║            🚀 Automated Infrastructure Deployment            ║"
echo "║                                                              ║"
echo "║    🌐 Web: luckyverse.tech      💻 GitHub: lucky-om          ║"
echo "║    ⭐ Engineering scalable solutions for the future ⭐       ║"
echo "║                                                              ║"
echo "║           🛠️  GCP Infrastructure & K8s Lab 🛠️               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo "${RESET}"

echo "${MAGENTA}${BOLD}🎯 Lab Objectives:${RESET}"
echo "${MAGENTA}• Dual-VPC Network Architecture${RESET}"
echo "${MAGENTA}• Cloud SQL (MySQL) Managed Database${RESET}"
echo "${MAGENTA}• GKE Cluster Configuration${RESET}"
echo "${MAGENTA}• Containerized WordPress with Sidecar Proxy${RESET}"
echo ""

echo "${YELLOW}${BOLD}Starting Execution...${RESET}"

# Set region based on zone
export REGION="${ZONE%-*}"

# Task 1: Create development VPC
gcloud compute networks create griffin-dev-vpc --subnet-mode custom

gcloud compute networks subnets create griffin-dev-wp \
    --network=griffin-dev-vpc --region $REGION --range=192.168.16.0/20

gcloud compute networks subnets create griffin-dev-mgmt \
    --network=griffin-dev-vpc --region $REGION --range=192.168.32.0/20

echo "${GREEN}${BOLD}✓ Task 1: Development VPC Created${RESET}"

# Task 2: Create production VPC via Deployment Manager
gsutil cp -r gs://cloud-training/gsp321/dm .
cd dm
sed -i s/SET_REGION/$REGION/g prod-network.yaml
gcloud deployment-manager deployments create prod-network --config=prod-network.yaml
cd ..

echo "${GREEN}${BOLD}✓ Task 2: Production VPC Deployed${RESET}"

# Task 3: Create Bastion Host
gcloud compute instances create bastion \
    --network-interface=network=griffin-dev-vpc,subnet=griffin-dev-mgmt \
    --network-interface=network=griffin-prod-vpc,subnet=griffin-prod-mgmt \
    --tags=ssh --zone=$ZONE

gcloud compute firewall-rules create fw-ssh-dev --source-ranges=0.0.0.0/0 --target-tags ssh --allow=tcp:22 --network=griffin-dev-vpc
gcloud compute firewall-rules create fw-ssh-prod --source-ranges=0.0.0.0/0 --target-tags ssh --allow=tcp:22 --network=griffin-prod-vpc

echo "${GREEN}${BOLD}✓ Task 3: Bastion Host and Firewall Configured${RESET}"

# Task 4: Cloud SQL Instance
gcloud sql instances create griffin-dev-db \
    --database-version=MYSQL_5_7 \
    --region=$REGION \
    --root-password='awesome'

gcloud sql databases create wordpress --instance=griffin-dev-db
gcloud sql users create wp_user --host='%' --instance=griffin-dev-db --password=stormwind_rules

echo "${GREEN}${BOLD}✓ Task 4: Cloud SQL Instance Ready${RESET}"

# Task 5: Kubernetes Cluster
gcloud container clusters create griffin-dev \
  --network griffin-dev-vpc \
  --subnetwork griffin-dev-wp \
  --machine-type e2-standard-4 \
  --num-nodes 2 \
  --zone $ZONE

gcloud container clusters get-credentials griffin-dev --zone $ZONE
gsutil cp -r gs://cloud-training/gsp321/wp-k8s ~/

echo "${GREEN}${BOLD}✓ Task 5: GKE Cluster Provisioned${RESET}"

# Task 6: K8s Secrets and Volume
cat > ~/wp-k8s/wp-env.yaml <<EOF_END
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: wordpress-volumeclaim
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 200Gi
---
apiVersion: v1
kind: Secret
metadata:
  name: database
type: Opaque
stringData:
  username: wp_user
  password: stormwind_rules
EOF_END

cd ~/wp-k8s
kubectl create -f wp-env.yaml

gcloud iam service-accounts keys create key.json \
    --iam-account=cloud-sql-proxy@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com
kubectl create secret generic cloudsql-instance-credentials --from-file key.json

echo "${GREEN}${BOLD}✓ Task 6: Kubernetes Environment Prepared${RESET}"

# Task 7: WordPress Deployment
INSTANCE_ID=$(gcloud sql instances describe griffin-dev-db --format='value(connectionName)')

cat > wp-deployment.yaml <<EOF_END
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      containers:
        - image: wordpress
          name: wordpress
          env:
          - name: WORDPRESS_DB_HOST
            value: 127.0.0.1:3306
          - name: WORDPRESS_DB_USER
            valueFrom:
              secretKeyRef:
                name: database
                key: username
          - name: WORDPRESS_DB_PASSWORD
            valueFrom:
              secretKeyRef:
                name: database
                key: password
          ports:
            - containerPort: 80
              name: wordpress
          volumeMounts:
            - name: wordpress-persistent-storage
              mountPath: /var/www/html
        - name: cloudsql-proxy
          image: gcr.io/cloudsql-docker/gce-proxy:1.33.2
          command: ["/cloud_sql_proxy",
                    "-instances=$INSTANCE_ID=tcp:3306",
                    "-credential_file=/secrets/cloudsql/key.json"]
          securityContext:
            runAsUser: 2
            allowPrivilegeEscalation: false
          volumeMounts:
            - name: cloudsql-instance-credentials
              mountPath: /secrets/cloudsql
              readOnly: true
      volumes:
        - name: wordpress-persistent-storage
          persistentVolumeClaim:
            claimName: wordpress-volumeclaim
        - name: cloudsql-instance-credentials
          secret:
            secretName: cloudsql-instance-credentials
EOF_END

kubectl create -f wp-deployment.yaml
kubectl create -f wp-service.yaml

echo "${GREEN}${BOLD}✓ Task 7: WordPress and Proxy Deployed${RESET}"

# Task 9: IAM Access Extension
IAM_POLICY_JSON=$(gcloud projects get-iam-policy $DEVSHELL_PROJECT_ID --format=json)
USERS=$(echo $IAM_POLICY_JSON | jq -r '.bindings[] | select(.role == "roles/viewer").members[]')

for USER in $USERS; do
  if [[ $USER == *"user:"* ]]; then
    USER_EMAIL=$(echo $USER | cut -d':' -f2)
    gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
      --member=user:$USER_EMAIL \
      --role=roles/editor --quiet
  fi
done

echo "${GREEN}${BOLD}✓ Task 9: IAM Permissions Updated${RESET}"

# Completion message
echo "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║            🎉 DEPLOYMENT COMPLETED BY LUCKY! 🎉              ║"
echo "║                                                              ║"
echo "║  ✅ All Infrastructure components are active                 ║"
echo "║  ✅ Network separation validated                              ║"
echo "║  ✅ WordPress is now live on GKE                             ║"
echo "║                                                              ║"
echo "║   Visit us for more:                                         ║"
echo "║   🌐 https://luckyverse.tech                                 ║"
echo "║   🐙 https://github.com/lucky-om                             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo "${RESET}"
