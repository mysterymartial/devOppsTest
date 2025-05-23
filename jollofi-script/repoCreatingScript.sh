!/bin/bash

# Function to run a command and handle errors
run_command() {
    local command="$1"
    local error_message="$2"
    local capture_output="$3"
    local output
    if [ "$capture_output" = "true" ]; then
        output=$(eval "$command" 2>&1)
        local exit_code=$?
        if [ $exit_code -ne 0 ]; then
            echo "$error_message: $output"
            return 1
        fi
        echo "$output"
    else
        eval "$command" 2>&1
        local exit_code=$?
        if [ $exit_code -ne 0 ]; then
            echo "$error_message"
            return 1
        fi
    fi
    return 0
}

# Function to validate y/n input
validate_yn() {
    local input="$1"
    input=$(echo "$input" | tr '[:upper:]' '[:lower:]')
    if [ "$input" != "y" ] && [ "$input" != "n" ]; then
        echo "Invalid input. Please enter 'y' or 'n'."
        return 1
    fi
    echo "$input"
    return 0
}

# Function to validate numeric input
validate_num() {
    local input="$1"
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        echo "Invalid input. Please enter a number."
        return 1
    fi
    echo "$input"
    return 0
}

# Function to check if GitHub CLI is installed
check_gh_installed() {
    if ! command -v gh >/dev/null 2>&1; then
        echo "GitHub CLI not installed."
        return 1
    fi
    return 0
}

# Function to authenticate with GitHub CLI
authenticate_gh() {
    local max_attempts=3
    local attempt=1
    local success=false
    echo "Logging in to GitHub..."
    if ! command -v winpty >/dev/null 2>&1; then
        echo "winpty not found. Please install Git for Windows with winpty or use cmd/PowerShell. Exiting."
        exit 1
    fi
    while [ $attempt -le $max_attempts ] && [ "$success" != "true" ]; do
        echo "Attempt $attempt/$max_attempts to authenticate via browser..."
        if run_command "winpty gh auth login --hostname github.com --git-protocol https --web -s repo,admin:org,delete_repo" \
                       "Failed to authenticate with GitHub" false; then
            success=true
        else
            if [ $attempt -eq $max_attempts ]; then
                echo "Maximum authentication attempts reached."
                read -p "Would you like to use a Personal Access Token instead? (y/n): " use_token
                use_token=$(validate_yn "$use_token") || {
                    echo "Invalid input. Exiting."
                    exit 1
                }
                if [ "$use_token" = "y" ]; then
                    read -p "Enter your GitHub username (for verification): " gh_username
                    gh_username=$(echo "$gh_username" | tr -d '[:space:]')
                    if [ -z "$gh_username" ]; then
                        echo "Username cannot be empty. Exiting."
                        exit 1
                    fi
                    read -s -p "Enter your GitHub Personal Access Token: " token
                    echo
                    if [ -z "$token" ]; then
                        echo "Token cannot be empty. Exiting."
                        exit 1
                    fi
                    if run_command "echo \"$token\" | gh auth login --with-token --hostname github.com --git-protocol https -s repo,admin:org,delete_repo" \
                                   "Failed to authenticate with token" false; then
                        success=true
                    else
                        echo "Token authentication failed. Exiting."
                        exit 1
                    fi
                else
                    echo "Authentication failed after $max_attempts attempts. Please check your network:"
                    echo "- Test connectivity: ping github.com"
                    echo "- Ensure port 443 is open: telnet github.com 443"
                    echo "- Disable firewall/antivirus temporarily to test."
                    echo "- If using a VPN/proxy, disable it and retry."
                    exit 1
                fi
            else
                read -p "Authentication failed. Retry? (y/n): " retry_choice
                retry_choice=$(validate_yn "$retry_choice") || {
                    echo "Invalid input. Exiting."
                    exit 1
                }
                if [ "$retry_choice" != "y" ]; then
                    echo "Authentication aborted. Please check your network:"
                    echo "- Test connectivity: ping github.com"
                    echo "- Ensure port 443 is open: telnet github.com 443"
                    echo "- Disable firewall/antivirus temporarily to test."
                    echo "- If using a VPN/proxy, disable it and retry."
                    exit 1
                fi
            fi
        fi
        attempt=$((attempt + 1))
    done
    if ! run_command "gh auth status" "Failed to verify authentication" true >/dev/null; then
        echo "Authentication unsuccessful. Exiting."
        exit 1
    fi
    gh_username=$(gh api user --jq .login)
    if [ -z "$gh_username" ]; then
        echo "Failed to retrieve GitHub username. Exiting."
        exit 1
    fi
    echo "Successfully logged in as $gh_username."
}

# Function to check if a repository exists
repo_exists() {
    local repo_name="$1"
    if run_command "gh repo view $repo_name" "Failed to check if $repo_name exists" true >/dev/null; then
        return 0
    fi
    return 1
}

# Function to check if a branch exists (locally or remotely)
branch_exists() {
    local repo_dir="$1"
    local branch_name="$2"
    local original_dir=$(pwd)
    cd "$repo_dir" || return 1
    # Check if branch exists locally
    if git show-ref --verify --quiet refs/heads/"$branch_name"; then
        cd "$original_dir"
        echo "$branch_name exists locally."
        return 0
    fi
    # Check if branch exists on remote
    if git show-ref --verify --quiet refs/remotes/origin/"$branch_name"; then
        cd "$original_dir"
        echo "$branch_name exists on remote."
        return 0
    fi
    cd "$original_dir"
    return 1
}

# Function to create a README.md file if it doesn't exist
create_readme() {
    local repo_dir="$1"
    local repo_name="$2"
    local readme_path="$repo_dir/README.md"
    if [ ! -d "$repo_dir" ]; then
        mkdir -p "$repo_dir" || { echo "Failed to create directory $repo_dir"; return 1; }
    fi
    if ! cd "$repo_dir" 2>/dev/null; then
        echo "Failed to change to directory $repo_dir"
        return 1
    fi
    if [ ! -f "README.md" ]; then
        echo "# $repo_name" > README.md
        echo "" >> README.md
        echo "This is the $repo_name repository." >> README.md
        if [ $? -ne 0 ]; then
            echo "Failed to create README.md in $repo_dir"
            cd - > /dev/null || return 1
            return 1
        fi
        cd - > /dev/null || return 1
        return 0
    fi
    cd - > /dev/null || return 1
    echo "README.md already exists in $repo_dir."
    return 1
}

# Function to check if a user exists
check_user_exists() {
    local username="$1"
    if run_command "gh api users/$username" "Failed to check if user $username exists" true >/dev/null 2>&1; then
        return 0
    fi
    echo "User $username does not exist or cannot be accessed."
    return 1
}

# Function to add collaborators
add_collaborators() {
    local repo_name="$1"
    read -p "How many collaborators to add to $repo_name? (enter 0 to skip): " num_collabs
    num_collabs=$(validate_num "$num_collabs") || { echo "Skipping collaborator addition."; return 1; }
    if [ "$num_collabs" -eq 0 ]; then
        echo "No collaborators will be added."
        return 0
    fi
    
    read -p "Assign 'push' (push/pull/review) or 'admin' (full access) permission? (push/admin): " perm_choice
    perm_choice=$(echo "$perm_choice" | tr '[:upper:]' '[:lower:]')
    if [ "$perm_choice" != "push" ] && [ "$perm_choice" != "admin" ]; then
        echo "Invalid permission. Defaulting to 'push'."
        perm_choice="push"
    fi
    
    owner=$(gh api user --jq .login)
    
    for ((j=1; j<=num_collabs; j++)); do
        read -p "Enter GitHub username for collaborator $j/$num_collabs: " username
        username=$(echo "$username" | tr -d '[:space:]')
        if [ -z "$username" ]; then
            echo "Username cannot be empty. Skipping."
            continue
        fi
        if ! check_user_exists "$username"; then
            continue
        fi
        read -p "Invite $username to $repo_name with $perm_choice permission? (y/n): " invite_choice
        invite_choice=$(validate_yn "$invite_choice") || continue
        if [ "$invite_choice" = "y" ]; then
            # Use the correct permission format for the GitHub API
            if run_command "gh api --method PUT repos/$owner/$repo_name/collaborators/$username -f permission=$perm_choice" \
                        "Failed to add $username to $repo_name" false; then
                echo "Invited $username to $repo_name with $perm_choice permission."
                
                # Skip forking for the same user to avoid the error
                if [ "$username" != "$owner" ]; then
                    echo "Note: The collaborator can fork the repository themselves from the GitHub web interface."
                fi
            else
                echo "Failed to add collaborator. GitHub API may have changed or there might be permission issues."
                continue
            fi
        else
            echo "Skipping invitation for $username."
        fi
    done
    return 0
}

# Main function to create repositories
create_repository() {
    if ! check_gh_installed; then
        echo "Please install GitHub CLI (gh): https://cli.github.com/"
        exit 1
    fi
    authenticate_gh
    read -p "Enter the number of repositories to create: " num_repos
    num_repos=$(validate_num "$num_repos") || { echo "Invalid number. Exiting."; exit 1; }
    for ((i=1; i<=num_repos; i++)); do
        echo -e "\nProcessing repository $i/$num_repos"
        read -p "Enter repository name: " repo_name
        repo_name=$(echo "$repo_name" | tr -d '[:space:]')
        if [ -z "$repo_name" ]; then
            echo "Repository name cannot be empty. Skipping."
            continue
        fi
        # Check if repository already exists
        if repo_exists "$repo_name"; then
            echo "Repository $repo_name already exists on GitHub."
            read -p "Clone and process existing repository? (y/n): " clone_choice
            clone_choice=$(validate_yn "$clone_choice") || continue
            if [ "$clone_choice" = "y" ]; then
                repo_dir="$repo_name"
                if [ ! -d "$repo_dir" ]; then
                    run_command "git clone https://github.com/$(gh api user --jq .login)/$repo_name.git" \
                                "Failed to clone $repo_name" false || continue
                else
                    echo "Local directory $repo_dir already exists."
                fi
                cd "$repo_dir" || continue
            else
                echo "Skipping $repo_name."
                continue
            fi
        else
            read -p "Create new repository $repo_name on GitHub? (y/n): " create_choice
            create_choice=$(validate_yn "$create_choice") || continue
            if [ "$create_choice" != "y" ]; then
                echo "Skipping repository creation for $repo_name."
                continue
            fi
            read -p "Enter repository description (press Enter to skip): " description
            read -p "Repository visibility (public/private): " visibility
            visibility=$(echo "$visibility" | tr '[:upper:]' '[:lower:]')
            if [ "$visibility" != "public" ] && [ "$visibility" != "private" ]; then
                echo "Invalid visibility. Defaulting to public."
                visibility="public"
            fi
            # Create local directory
            repo_dir="$repo_name"
            read -p "Create local directory $repo_dir? (y/n): " dir_choice
            dir_choice=$(validate_yn "$dir_choice") || continue
            if [ "$dir_choice" = "y" ]; then
                mkdir -p "$repo_dir" || { echo "Failed to create directory $repo_dir"; continue; }
                cd "$repo_dir" || { echo "Failed to change to directory $repo_dir"; cd ..; continue; }
            else
                echo "Skipping directory creation for $repo_name."
                continue
            fi
            # Initialize git
            if [ ! -d ".git" ]; then
                read -p "Initialize git repository in $repo_dir? (y/n): " init_choice
                init_choice=$(validate_yn "$init_choice") || { cd ..; continue; }
                if [ "$init_choice" = "y" ]; then
                    run_command "git init" "Failed to initialize git repository" false || { cd ..; continue; }
                    # Set remote origin
                    owner=$(gh api user --jq .login)
                    run_command "git remote add origin https://github.com/$owner/$repo_name.git" \
                                "Failed to set remote origin" false || { cd ..; continue; }
                else
                    echo "Skipping git initialization for $repo_name."
                    cd ..
                    continue
                fi
            else
                echo "Git repository already initialized."
            fi
            # Create README
            read -p "Create README.md file for $repo_name? (y/n): " include_readme
            include_readme=$(validate_yn "$include_readme") || { cd ..; continue; }
            if [ "$include_readme" = "y" ]; then
                if create_readme "$repo_dir" "$repo_name"; then
                    read -p "Stage and commit README.md? (y/n): " commit_readme
                    commit_readme=$(validate_yn "$commit_readme") || { cd ..; continue; }
                    if [ "$commit_readme" = "y" ]; then
                        cd "$repo_dir" || { echo "Failed to change to $repo_dir for commit"; cd ..; continue; }
                        if [ -f "README.md" ]; then
                            run_command "git add README.md" "Failed to stage README" false
                            run_command "git commit -m \"Initial commit with README\"" "Failed to commit README" false
                        else
                            echo "README.md not found in $repo_dir. Skipping commit."
                        fi
                        cd - > /dev/null || { cd ..; continue; }
                    else
                        echo "Skipping README commit."
                    fi
                fi
            fi

              
		# Create repository on GitHub
            description_flag=""
            [ -n "$description" ] && description_flag="--description \"$description\""
            run_command "gh repo create $repo_name --$visibility $description_flag" \
                        "Failed to create repository $repo_name" false || { cd ..; continue; }
            # Push initial commit if it exists
            if [ -n "$(git log 2>/dev/null)" ]; then
                run_command "git push -u origin master" "Failed to push initial commit to GitHub" false
            fi
        fi
        # Add collaborators
        add_collaborators "$repo_name" || { cd ..; continue; }
        # Set up branches
        read -p "How many branches to create for $repo_name? (enter 0 to skip): " num_branches
        num_branches=$(validate_num "$num_branches") || { echo "Skipping branch creation."; cd ..; continue; }
        if [ "$num_branches" -gt 0 ]; then
            for ((b=1; b<=num_branches; b++)); do
                read -p "Enter name for branch $b/$num_branches: " branch_name
                branch_name=$(echo "$branch_name" | tr -d '[:space:]')
                if [ -z "$branch_name" ]; then
                    echo "Branch name cannot be empty. Skipping this branch."
                    continue
                fi
                if ! branch_exists "$repo_dir" "$branch_name"; then
                    read -p "Create and push $branch_name branch? (y/n): " branch_choice
                    branch_choice=$(validate_yn "$branch_choice") || continue
                    if [ "$branch_choice" = "y" ]; then
                        cd "$repo_dir" || { echo "Failed to change to $repo_dir for branch creation"; cd ..; continue; }
                        run_command "git checkout -b $branch_name" "Failed to create $branch_name branch" false
                        # Ensure there is a commit before pushing
                        if [ -z "$(git log 2>/dev/null)" ]; then
                            # Create a dummy commit if no commits exist
                            touch .gitignore
                            git add .gitignore
                            run_command "git commit -m \"Add .gitignore to enable branch push\"" \
                                        "Failed to create dummy commit for $branch_name" false
                        fi
                        run_command "git push -u origin $branch_name" "Failed to push $branch_name branch" false
                        cd - > /dev/null || { cd ..; continue; }
                    else
                        echo "Skipping $branch_name branch creation."
                    fi
                fi
            done
        fi
        echo "Repository $repo_name processed successfully."
        cd ..
    done
    echo -e "\nAll repositories processed."
    # Prompt to delete the last created repository
    if [ $num_repos -gt 0 ]; then
        last_repo="$(gh api user --jq .login)/${repo_name}"
        read -p "Do you want to delete the last created repository ($last_repo)? (y/n): " delete_choice
        delete_choice=$(validate_yn "$delete_choice") || {
            echo "Invalid input for deletion choice. Skipping deletion."
            return 1
        }
        if [ "$delete_choice" = "y" ]; then
            run_command "gh repo delete $last_repo --yes" \
                        "Failed to delete repository $last_repo" false && \
            echo "Repository $last_repo has been deleted."
        else
            echo "Repository deletion skipped."
        fi
    fi
}

# Run the main function
create_repository