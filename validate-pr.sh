#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CHANGELOG_DIR="${CHANGELOG_DIR:-.changelog}"
REQUIRED_VERSION_BUMPS=("patch" "minor" "major")

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to post a comment to the PR
post_pr_comment() {
    local pr_number=$1
    local comment_body="$2"
    
    log_info "Posting comment to PR #${pr_number}..."
    
    # Escape JSON special characters in the comment body
    local escaped_body=$(echo "$comment_body" | jq -R -s .)
    
    # Create the JSON payload
    local payload="{\"body\": $escaped_body}"
    
    # Post the comment using GitHub API
    curl -s \
        -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${pr_number}/comments" \
        -d "$payload" > /dev/null
    
    if [[ $? -eq 0 ]]; then
        log_info "Comment posted successfully"
    else
        log_warn "Failed to post comment to PR"
    fi
}

# Function to update or create a PR comment (to avoid spam)
update_or_create_pr_comment() {
    local pr_number=$1
    local comment_body="$2"
    local comment_identifier="<!-- pr-data-validation-bot -->"
    
    log_info "Checking for existing validation comments..."
    
    # Get existing comments from the PR
    local existing_comments=$(curl -s \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${pr_number}/comments")
    
    # Look for existing comment with our identifier
    local existing_comment_id=$(echo "$existing_comments" | jq -r ".[] | select(.body | contains(\"$comment_identifier\")) | .id" | head -1)
    
    # Prepare the comment with identifier
    local full_comment_body="${comment_identifier}\n${comment_body}"
    local escaped_body=$(echo -e "$full_comment_body" | jq -R -s .)
    local payload="{\"body\": $escaped_body}"
    
    if [[ -n "$existing_comment_id" && "$existing_comment_id" != "null" ]]; then
        # Update existing comment
        log_info "Updating existing validation comment (ID: $existing_comment_id)"
        curl -s \
            -X PATCH \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            -H "Content-Type: application/json" \
            "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/comments/${existing_comment_id}" \
            -d "$payload" > /dev/null
    else
        # Create new comment
        log_info "Creating new validation comment"
        curl -s \
            -X POST \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            -H "Content-Type: application/json" \
            "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${pr_number}/comments" \
            -d "$payload" > /dev/null
    fi
    
    if [[ $? -eq 0 ]]; then
        log_info "PR comment updated successfully"
    else
        log_warn "Failed to update PR comment"
    fi
}

# Function to create success message
create_success_message() {
    local version_bump_type="$1"
    cat << EOF
## ✅ PR Validation Passed

Great job! Your pull request meets all the requirements:

- **Changelog**: Found changelog file in \`${CHANGELOG_DIR}/\` directory
- **Version Bump**: Found valid \`Version-Bump: ${version_bump_type}\` trailer

Your PR is ready for review! 🚀
EOF
}

# Function to create failure message
create_failure_message() {
    local missing_changelog="$1"
    local missing_version_bump="$2"
    local issues=""
    
    if [[ "$missing_changelog" == "true" ]]; then
        issues+="- **Missing Changelog File** ❌\n"
        issues+="  Please add a changelog file to document your changes:\n"
        issues+="  1. Create a new file in the \`${CHANGELOG_DIR}/\` directory\n"
        issues+="  2. Name it descriptively (e.g., \`fix-bug-123.md\`, \`add-new-feature.md\`)\n"
        issues+="  3. Document what changed, why, and any breaking changes\n\n"
    fi
    
    if [[ "$missing_version_bump" == "true" ]]; then
        issues+="- **Missing Version Bump Trailer** ❌\n"
        issues+="  Please add a Version-Bump trailer to one of your commits:\n"
        issues+="  1. Edit your commit message to include one of:\n"
        issues+="     - \`Version-Bump: patch\`   (for bug fixes)\n"
        issues+="     - \`Version-Bump: minor\`   (for new features)\n"
        issues+="     - \`Version-Bump: major\`   (for breaking changes)\n"
        issues+="  2. The trailer should be on its own line at the end of the commit message\n\n"
        issues+="  **Example commit message:**\n"
        issues+="  \`\`\`\n"
        issues+="  Fix critical bug in user authentication\n\n"
        issues+="  This fixes an issue where users couldn't log in\n"
        issues+="  after password reset.\n\n"
        issues+="  Version-Bump: patch\n"
        issues+="  \`\`\`\n"
    fi
    
    cat << EOF
## ❌ PR Validation Failed

Your pull request needs some updates before it can be merged:

${issues}
Please fix the issues above and push your changes. This comment will be updated automatically when you make changes.
EOF
}

# Check if we're in a pull request context
check_pr_context() {
    if [[ "${GITHUB_EVENT_NAME}" != "pull_request" ]]; then
        log_error "This action should only run on pull request events"
        exit 1
    fi
}

# Get PR number from GitHub context
get_pr_number() {
    if [[ -f "${GITHUB_EVENT_PATH}" ]]; then
        # Extract PR number directly from the event JSON using jq
        PR_NUMBER=$(jq -r '.pull_request.number' "${GITHUB_EVENT_PATH}")

        if [[ -z "${PR_NUMBER}" || "${PR_NUMBER}" == "null" ]]; then
            log_error "Could not extract PR number from event data"
            exit 1
        fi

        echo "${PR_NUMBER}"
    else
        log_error "GITHUB_EVENT_PATH is not set or file does not exist"
        exit 1
    fi
}

# Get list of files changed in the PR
get_changed_files() {
    local pr_number=$1
    
    # Use GitHub API to get PR files
    curl -s \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls/${pr_number}/files" \
        | jq -r '.[].filename'
}

# Check if changelog file exists in changed files
check_changelog_file() {
    local changed_files="$1"
    local changelog_found=false
    
    log_info "Checking for changelog files in ${CHANGELOG_DIR}/ directory..."
    
    while IFS= read -r file; do
        if [[ "${file}" == "${CHANGELOG_DIR}/"* ]]; then
            log_info "Found changelog file: ${file}"
            changelog_found=true
            break
        fi
    done <<< "${changed_files}"
    
    if [[ "${changelog_found}" == "false" ]]; then
        log_error "No changelog file found in ${CHANGELOG_DIR}/ directory"
        echo ""
        echo "📝 Please add a changelog file to document your changes:"
        echo "   1. Create a new file in the ${CHANGELOG_DIR}/ directory"
        echo "   2. Name it descriptively (e.g., fix-bug-123.md, add-new-feature.md)"
        echo "   3. Document what changed, why, and any breaking changes"
        echo ""
        return 1
    fi
    
    return 0
}

# Get commit messages for the PR
get_pr_commits() {
    local pr_number=$1
    log_info "Fetching commits for PR #${pr_number}..."
    
    # Use GitHub API to get PR commits
    curl -s \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls/${pr_number}/commits" \
        | jq -r '.[].commit.message'
}

# Check for version bump trailer in commit messages
check_version_bump_trailer() {
    local commit_messages="$1"
    local version_bump_found=false
    local version_bump_type=""
    
    log_info "Checking for Version-Bump trailer in commit messages..."
    
    while IFS= read -r message; do
        # Look for Version-Bump: trailer (case insensitive)
        if echo "${message}" | grep -qi "Version-Bump:"; then
            # Extract the value after Version-Bump:
            bump_value=$(echo "${message}" | grep -oiE "Version-Bump:\s*(patch|minor|major)" | cut -d':' -f2 | xargs | tr '[:upper:]' '[:lower:]')
            
            if [[ -n "${bump_value}" ]]; then
                # Validate the bump value
                for valid_bump in "${REQUIRED_VERSION_BUMPS[@]}"; do
                    if [[ "${bump_value}" == "${valid_bump}" ]]; then
                        log_info "Found valid Version-Bump trailer: ${bump_value}"
                        version_bump_found=true
                        version_bump_type="${bump_value}"
                        break 2
                    fi
                done
            fi
        fi
    done <<< "${commit_messages}"
    
    if [[ "${version_bump_found}" == "false" ]]; then
        log_error "No valid Version-Bump trailer found in commit messages"
        echo ""
        echo "🏷️  Please add a Version-Bump trailer to one of your commits:"
        echo "   1. Edit your commit message to include one of:"
        echo "      - Version-Bump: patch   (for bug fixes)"
        echo "      - Version-Bump: minor   (for new features)"
        echo "      - Version-Bump: major   (for breaking changes)"
        echo "   2. The trailer should be on its own line at the end of the commit message"
        echo ""
        echo "Example commit message:"
        echo "Fix critical bug in user authentication"
        echo ""
        echo "This fixes an issue where users couldn't log in"
        echo "after password reset."
        echo ""
        echo "Version-Bump: patch"
        echo ""
        return 1
    fi
    
    return 0
}

# Main validation function
main() {
    log_info "Starting PR data validation..."
    
    # Check if we're in the right context
    check_pr_context
    
    # Get PR number
    PR_NUMBER=$(get_pr_number)
    log_info "Validating PR #${PR_NUMBER}"
    
    # Get changed files
    CHANGED_FILES=$(get_changed_files "${PR_NUMBER}")
    log_info "Changed files in PR:"
    echo "${CHANGED_FILES}"
    if [[ -z "${CHANGED_FILES}" ]]; then
        log_warn "No files changed in this PR"
        return 0
    fi
    
    # Check for changelog file
    changelog_check_passed=true
    missing_changelog="false"
    if ! check_changelog_file "${CHANGED_FILES}"; then
        changelog_check_passed=false
        missing_changelog="true"
    fi
    
    # Get commit messages
    COMMIT_MESSAGES=$(get_pr_commits "${PR_NUMBER}")
    if [[ -z "${COMMIT_MESSAGES}" ]]; then
        log_error "No commit messages found for this PR"
        exit 1
    fi
    
    # Check for version bump trailer
    version_bump_check_passed=true
    missing_version_bump="false"
    found_version_bump_type=""
    
    # Store the original check_version_bump_trailer output
    if check_version_bump_trailer "${COMMIT_MESSAGES}"; then
        # Extract the version bump type from the function's output
        found_version_bump_type=$(echo "${COMMIT_MESSAGES}" | while IFS= read -r message; do
            if echo "${message}" | grep -qi "Version-Bump:"; then
                bump_value=$(echo "${message}" | grep -oiE "Version-Bump:\s*(patch|minor|major)" | cut -d':' -f2 | xargs | tr '[:upper:]' '[:lower:]')
                if [[ -n "${bump_value}" ]]; then
                    for valid_bump in "${REQUIRED_VERSION_BUMPS[@]}"; do
                        if [[ "${bump_value}" == "${valid_bump}" ]]; then
                            echo "${bump_value}"
                            break 2
                        fi
                    done
                fi
            fi
        done | head -1)
    else
        version_bump_check_passed=false
        missing_version_bump="true"
    fi
    
    # Final validation result and PR comment
    if [[ "${changelog_check_passed}" == "true" && "${version_bump_check_passed}" == "true" ]]; then
        log_info "✅ All PR data validation checks passed!"
        
        # Set outputs
        echo "changelog-found=true" >> $GITHUB_OUTPUT
        echo "version-bump-found=true" >> $GITHUB_OUTPUT
        echo "version-bump-type=${found_version_bump_type}" >> $GITHUB_OUTPUT
        
        # Post success comment
        update_or_create_pr_comment "${PR_NUMBER}" "$(create_success_message "${found_version_bump_type}")"
        exit 0
    else
        log_error "❌ PR data validation failed"
        
        # Set outputs
        echo "changelog-found=${changelog_check_passed}" >> $GITHUB_OUTPUT
        echo "version-bump-found=${version_bump_check_passed}" >> $GITHUB_OUTPUT
        echo "version-bump-type=" >> $GITHUB_OUTPUT
        
        # Post failure comment
        update_or_create_pr_comment "${PR_NUMBER}" "$(create_failure_message "${missing_changelog}" "${missing_version_bump}")"
        
        echo ""
        echo "Please fix the issues above and push your changes."
        exit 1
    fi
}

# Run main function
main "$@"
