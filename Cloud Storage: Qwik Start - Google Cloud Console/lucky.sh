export PROJECT_ID=$(gcloud config get-value project)

gsutil mb -l $REGION -c Standard gs://$PROJECT_ID

# Corrected URL to fetch the raw image file from LuckyVerse
curl -L -o kitten.png https://github.com/lucky-om/GoogleCloudSkillsboost/raw/f31d8eff4b56e6b72b256884cf4fc62d17fc58fa/Cloud%20Storage%3A%20Qwik%20Start%20-%20Cloud%20Console/kitten.png

gsutil cp kitten.png gs://$PROJECT_ID/kitten.png

gsutil iam ch allUsers:objectViewer gs://$PROJECT_ID

echo "Visit: https://luckyverse.tech"
