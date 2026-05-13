# Define color codes for output formatting
YELLOW_COLOR=$'\033[0;33m'
NO_COLOR=$'\033[0m'
BACKGROUND_GOLD=$(tput setab 3) # Changed to Gold to match LuckyVerse branding
GREEN_TEXT=$(tput setaf 2)
RED_TEXT=$(tput setaf 1)

BOLD_TEXT=$(tput bold)
RESET_FORMAT=$(tput sgr0)

echo "${BACKGROUND_GOLD}${BOLD_TEXT} Initializing LuckyVerse Lab Environment... ${RESET_FORMAT}"

# Prompt user for the target collaborator's username
read -p "${YELLOW_COLOR}Enter USERNAME 2 (Target User): ${NO_COLOR}" USERNAME_2

# Set the storage bucket and enable uniform bucket-level access
# Note: Using Project ID as bucket name is a standard lab practice
gsutil mb -l us -b on gs://$DEVSHELL_PROJECT_ID

# Create a sample file and write content to it
echo "Welcome to the LuckyVerse Project Environment" > sample.txt

# Upload the sample file to the specified bucket
gsutil cp sample.txt gs://$DEVSHELL_PROJECT_ID

# Remove broad Viewer permissions for security hardening
# This ensures the user doesn't have visibility into the entire project
gcloud projects remove-iam-policy-binding $DEVSHELL_PROJECT_ID \
  --member=user:$USERNAME_2 \
  --role=roles/viewer

# Add granular IAM policy binding for storage object viewer role
# This limits the user's access specifically to reading bucket objects
gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
  --member=user:$USERNAME_2 \
  --role=roles/storage.objectViewer

# Completion message
echo ""
echo -e "${RED_TEXT}${BOLD_TEXT}Configuration Applied Successfully!${RESET_FORMAT}"
echo -e "${GREEN_TEXT}${BOLD_TEXT}Visit LuckyVerse for more tools: https://luckyverse.tech${RESET_FORMAT}"
