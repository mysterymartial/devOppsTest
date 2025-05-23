import os
import subprocess
import getpass
import json

def run_command(command, error_message, capture_output=True):
    """Run a shell command and handle errors."""
    try:
        result = subprocess.run(command, shell=True, check=True, text=True, capture_output=capture_output)
        return result.stdout if capture_output else None
    except subprocess.CalledProcessError as e:
        print(f"{error_message}: {e.stderr}")
        return None

def check_gh_installed():
    """Check if GitHub CLI is installed."""
    return run_command("gh --version", "GitHub CLI not installed") is not None

def authenticate_gh():
    """Prompt user to authenticate with GitHub CLI if not logged in."""
    if run_command("gh auth status", "Failed to check GitHub auth status") is None:
        print("GitHub CLI not authenticated.")
        choice = input("Authenticate now? (y/n): ").lower()
        if choice == 'y':
            print("Choose authentication method:")
            print("1. Browser")
            print("2. Personal Access Token")
            auth_method = input("Enter choice (1/2): ")
            if auth_method == '1':
                run_command("gh auth login --web", "Failed to authenticate via browser")
            elif auth_method == '2':
                token = getpass.getpass("Enter GitHub Personal Access Token: ")
                run_command(f"echo {token} | gh auth login --with-token", "Failed to authenticate with token")
            else:
                print("Invalid choice. Exiting.")
                exit(1)
            if run_command("gh auth status", "Authentication failed") is None:
                print("Authentication unsuccessful. Exiting.")
                exit(1)
            print("Authentication successful.")
        else:
            print("Authentication required to proceed. Exiting.")
            exit(1)

def repo_exists(repo_name):
    """Check if a repository exists for the authenticated user."""
    output = run_command(f"gh repo view {repo_name}", f"Failed to check if {repo_name} exists", capture_output=True)
    return output is not None

def branch_exists(repo_dir, branch_name):
    """Check if a branch exists in the repository."""
    os.chdir(repo_dir)
    output = run_command(f"git show-ref --verify --quiet refs/heads/{branch_name}", 
                        f"Failed to check branch {branch_name}", capture_output=False)
    os.chdir("..")
    return output is None  # Returns True if branch exists (command succeeds)

def create_readme(repo_dir, repo_name):
    """Create a README.md file if it doesn't exist."""
    readme_path = os.path.join(repo_dir, "README.md")
    if not os.path.exists(readme_path):
        readme_content = f"# {repo_name}\n\nThis is the {repo_name} repository."
        with open(readme_path, "w") as f:
            f.write(readme_content)
        return True
    return False

def create_repository():
    """Prompt user for repo details and create repositories if they don't exist."""
    if not check_gh_installed():
        print("Please install GitHub CLI (gh) first: https://cli.github.com/")
        exit(1)

    authenticate_gh()

    try:
        num_repos = int(input("Enter the number of repositories to create: "))
    except ValueError:
        print("Invalid number. Exiting.")
        exit(1)

    for i in range(num_repos):
        print(f"\nProcessing repository {i + 1}/{num_repos}")
        repo_name = input("Enter repository name: ").strip()
        if not repo_name:
            print("Repository name cannot be empty. Skipping.")
            continue

        # Check if repository already exists
        if repo_exists(repo_name):
            print(f"Repository {repo_name} already exists. Skipping creation.")
            continue

        include_readme = input("Create README.md file? (y/n): ").lower() == 'y'
        description = input("Enter repository description (press Enter to skip): ").strip()
        visibility = input("Repository visibility (public/private): ").lower()
        if visibility not in ['public', 'private']:
            print("Invalid visibility. Defaulting to public.")
            visibility = 'public'

        # Create local directory
        repo_dir = repo_name
        os.makedirs(repo_dir, exist_ok=True)
        os.chdir(repo_dir)

        # Initialize git if not already initialized
        if not os.path.exists(".git"):
            if not run_command("git init", "Failed to initialize git repository"):
                os.chdir("..")
                continue
        else:
            print("Git repository already initialized.")

        # Create README if requested
        if include_readme:
            if create_readme(repo_dir, repo_name):
                run_command("git add README.md", "Failed to stage README")
                run_command('git commit -m "Add README"', "Failed to commit README")

        # Create repository on GitHub if it doesn't exist
        description_flag = f"--description \"{description}\"" if description else ""
        if not run_command(f"gh repo create {repo_name} --{visibility} {description_flag} --confirm", 
                          f"Failed to create repository {repo_name}"):
            os.chdir("..")
            continue

        # Set up main branch if it doesn't exist
        if not branch_exists(repo_dir, "main"):
            run_command("git checkout -b main", "Failed to create main branch")
            run_command("git push origin main", "Failed to push main branch")
        else:
            print("Main branch already exists.")

        # Set up dev branch if it doesn't exist
        if not branch_exists(repo_dir, "dev"):
            run_command("git checkout -b dev", "Failed to create dev branch")
            run_command("git push origin dev", "Failed to push dev branch")
        else:
            print("Dev branch already exists.")

        print(f"Repository {repo_name} processed with main and dev branches.")
        os.chdir("..")

if __name__ == "__main__":
    create_repository()