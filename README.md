# PR Data Validation Action

A GitHub Action that validates pull requests contain both:
1. A new file in the `.changelog` directory
2. A commit with a `Version-Bump:` trailer specifying `patch`, `minor`, or `major`

## Usage

Add this action to your workflow file (e.g., `.github/workflows/pr-validation.yml`):

```yaml
name: PR Validation
on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - name: Validate PR Data
        uses: your-username/pr-data-action@v1
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          changelog-dir: '.changelog'  # Optional, defaults to '.changelog'
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `token` | GitHub token for API access | Yes | `${{ github.token }}` |
| `changelog-dir` | Directory where changelog files should be located | No | `.changelog` |

## Outputs

| Output | Description |
|--------|-------------|
| `changelog-found` | Whether a changelog file was found |
| `version-bump-found` | Whether a valid version bump trailer was found |
| `version-bump-type` | The type of version bump (patch, minor, major) |

## What it checks

### 1. Changelog File
The action checks if the PR includes any new or modified files in the specified changelog directory (`.changelog` by default).

**Example changelog file structure:**
```
.changelog/
├── fix-login-bug.md
├── add-user-profile.md
└── breaking-change-api.md
```

### 2. Version Bump Trailer
The action looks for a `Version-Bump:` trailer in any of the commit messages in the PR.

**Valid version bump values:**
- `patch` - for bug fixes and small changes
- `minor` - for new features (backward compatible)
- `major` - for breaking changes

**Example commit message:**
```
Fix critical authentication bug

This resolves an issue where users couldn't log in
after password reset.

Version-Bump: patch
```

## PR Comments

The action automatically posts comments to the PR using the `github-actions[bot]` account:

### ✅ Success Comment
When all validations pass, a success comment is posted:
```
✅ PR Validation Passed

Great job! Your pull request meets all the requirements:

- Changelog: Found changelog file in `.changelog/` directory
- Version Bump: Found valid `Version-Bump: patch` trailer

Your PR is ready for review! 🚀
```

### ❌ Failure Comment
When validation fails, a detailed comment explains what needs to be fixed:
```
❌ PR Validation Failed

Your pull request needs some updates before it can be merged:

- Missing Changelog File ❌
  Please add a changelog file to document your changes:
  1. Create a new file in the `.changelog/` directory
  2. Name it descriptively (e.g., `fix-bug-123.md`, `add-new-feature.md`)
  3. Document what changed, why, and any breaking changes

Please fix the issues above and push your changes. This comment will be updated automatically when you make changes.
```

**Note**: The action will update the same comment rather than creating multiple comments, keeping the PR conversation clean.

## Error Messages

The action provides helpful error messages when validation fails:

### Missing Changelog
```
📝 Please add a changelog file to document your changes:
   1. Create a new file in the .changelog/ directory
   2. Name it descriptively (e.g., fix-bug-123.md, add-new-feature.md)
   3. Document what changed, why, and any breaking changes
```

### Missing Version Bump
```
🏷️  Please add a Version-Bump trailer to one of your commits:
   1. Edit your commit message to include one of:
      - Version-Bump: patch   (for bug fixes)
      - Version-Bump: minor   (for new features)
      - Version-Bump: major   (for breaking changes)
   2. The trailer should be on its own line at the end of the commit message
```

## Development

This action is implemented as a composite action using shell scripts, making it simple and dependency-free.

### Files
- `action.yml` - Action metadata and configuration
- `validate-pr.sh` - Main validation script

### Testing
You can test the action locally by setting the required environment variables:

```bash
export GITHUB_TOKEN="your-token"
export GITHUB_REPOSITORY="owner/repo"
export GITHUB_EVENT_NAME="pull_request"
export GITHUB_EVENT_PATH="/path/to/event.json"
export CHANGELOG_DIR=".changelog"

./validate-pr.sh
```
