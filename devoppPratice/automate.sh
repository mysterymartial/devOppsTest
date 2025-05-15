#!/bin/bash
set -e


ROOT_FOLDER="DEVOPPPRACTICE"
REPO_NAME="devoppspractice"


mkdir -p "$ROOT_FOLDER/.github/workflows"
cd "$ROOT_FOLDER" || exit


cat <<EOF > ".github/workflows/build.yml"
name: Build

on:
  push:
    branches:
      - main
      - dev

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run a sample script
        run: echo "Hello, GitHub Actions!"
EOF


echo "# $ROOT_FOLDER" > "README.md"


git init
git add .
git commit -m "Initial commit"

if ! git show-ref --verify --quiet refs/heads/main; then
  echo "Main branch does not exist. Creating main branch."
  else
    echo "Main branch already exists. Skipping creation."
fi

gh repo create "$REPO_NAME" --public --source=. --remote=origin --push


if ! git show-ref --verify --quiet refs/heads/dev; then
  git checkout -b dev
  git push origin dev
else
    echo "Branch 'dev' already exists. Skipping creation."
fi


gh api \
  -X PUT \
  -H "Accept: application/vnd.github+json" \
  "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/collaborators/Arewa100" \
  -f permission=push

echo " Script completed successfully!"
