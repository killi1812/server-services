#!/bin/bash

# --- Configuration ---
# Define the name of the Docker Compose file to use
COMPOSE_FILE="deploy.yaml"

# Define the base working directory (using $HOME for robust path expansion)
WORKING_DIR="$HOME/webapps"

# --- Input Parameter Check ---
# Check if the GitHub repository URL was provided as the first argument ($1)
if [ -z "$1" ]; then
    echo "❌ ERROR: Missing repository URL."
    echo "Usage: $0 <GitHub_Repository_URL>"
    echo "Example: $0 https://github.com/my-user/my-app.git"
    exit 1
fi

# Set the URL from the command-line parameter
REPO_URL="$1"

# Extract the repository name from the URL for the local directory name
# Example: 'https://github.com/user/repo.git' -> 'repo'
REPO_NAME=$(basename -s .git "$REPO_URL")

# --- Deployment Function ---
# This function centralizes the docker compose command to keep the main logic clean.
deploy() {
    echo "--- Deploying services with Docker Compose ---"
    # This command runs inside the repository directory ($REPO_NAME)
    docker compose -f="$COMPOSE_FILE" up --build -d
    
    if [ $? -eq 0 ]; then
        echo "✅ Deployment successful. Services are running in detached mode."
    else
        echo "❌ ERROR: Docker Compose failed. Check the logs above."
        exit 1
    fi
}

# --- Main Logic ---

echo "Starting deployment process for repository: $REPO_NAME"

# 1. Navigate to the desired working directory
echo "Setting base deployment directory to: $WORKING_DIR"
# Create the directory if it doesn't exist
mkdir -p "$WORKING_DIR"
# Change to the base directory
cd "$WORKING_DIR" || { echo "❌ ERROR: Could not change directory to $WORKING_DIR."; exit 1; }

# 2. Check if the repository directory already exists inside $WORKING_DIR
if [ -d "$REPO_NAME" ]; then
    echo "Directory '$REPO_NAME' found. Updating existing repository..."

    # Change into the repository directory (relative to $WORKING_DIR)
    cd "$REPO_NAME" || { echo "❌ ERROR: Could not change directory to $REPO_NAME within $WORKING_DIR."; exit 1; }

    # Pull the latest changes
    git pull
    
    # Run the deployment command
    deploy

else
    echo "Directory '$REPO_NAME' not found. Cloning repository into $WORKING_DIR..."

    # Clone the repository (it will clone into $WORKING_DIR)
    git clone "$REPO_URL"
    
    if [ $? -ne 0 ]; then
        echo "❌ ERROR: Git clone failed for $REPO_URL."
        exit 1
    fi

    # Change into the newly cloned repository directory
    cd "$REPO_NAME" || { echo "❌ ERROR: Could not change directory to $REPO_NAME after cloning."; exit 1; }
    
    # Run the deployment command
    deploy
fi

echo "Deployment script finished."
