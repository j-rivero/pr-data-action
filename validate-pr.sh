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
    
    # Set outputs
    echo "changelog-found=true" >> $GITHUB_OUTPUT
    echo "version-bump-found=true" >> $GITHUB_OUTPUT
    echo "version-bump-type=${version_bump_type}" >> $GITHUB_OUTPUT
    
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
    if ! check_changelog_file "${CHANGED_FILES}"; then
        changelog_check_passed=false
    fi
    
    # Get commit messages
    COMMIT_MESSAGES=$(get_pr_commits "${PR_NUMBER}")
    if [[ -z "${COMMIT_MESSAGES}" ]]; then
        log_error "No commit messages found for this PR"
        exit 1
    fi
    
    # Check for version bump trailer
    version_bump_check_passed=true
    if ! check_version_bump_trailer "${COMMIT_MESSAGES}"; then
        version_bump_check_passed=false
    fi
    
    # Final validation result
    if [[ "${changelog_check_passed}" == "true" && "${version_bump_check_passed}" == "true" ]]; then
        log_info "✅ All PR data validation checks passed!"
        exit 0
    else
        log_error "❌ PR data validation failed"
        echo ""
        echo "Please fix the issues above and push your changes."
        exit 1
    fi
}

# Run main function
main "$@"
