# Contributing to GCP Resource Audit & Cleanup

Thank you for your interest in contributing to the GCP Resource Audit & Cleanup project. This guide will help you understand our development process and how you can effectively contribute to making this tool even better. We value every contribution, whether it's code, documentation, testing, or bug reports.

## Our Philosophy

We believe in creating robust, maintainable, and secure tools for cloud resource management. Our development philosophy centers around these key principles:

Safety First: Every change must prioritize data safety and system stability. We implement multiple layers of validation and verification to prevent unintended resource modifications.

Clear Documentation: We believe good documentation is as important as good code. Every feature should be well-documented, with clear examples and explanations of both what it does and why it exists.

Comprehensive Testing: Our testing strategy ensures reliability across different environments and use cases. We value thorough testing and consider it an essential part of the development process.

## Code of Conduct

Our community welcomes contributors from all backgrounds and experience levels. We maintain a respectful and inclusive environment where everyone can contribute effectively. We expect all participants to:

- Use welcoming and inclusive language
- Respect differing viewpoints and experiences
- Accept constructive criticism gracefully
- Focus on what's best for the community
- Show empathy toward other community members

## Getting Started with Development

Before you begin contributing, let's set up your development environment properly. This process involves several important steps:

### 1. Environment Setup

First, ensure your system meets these core requirements:

```bash
# Check your Bash version (must be 4.0+)
bash --version

# Check for or install required tools
command -v shellcheck >/dev/null 2>&1 || {
    echo "Installing shellcheck..."
    # For Ubuntu/Debian
    sudo apt-get update && sudo apt-get install -y shellcheck
    # For macOS
    brew install shellcheck
}

command -v bats >/dev/null 2>&1 || {
    echo "Installing bats testing framework..."
    # For Ubuntu/Debian
    sudo apt-get update && sudo apt-get install -y bats
    # For macOS
    brew install bats-core
}
```

### 2. Repository Setup

Clone and configure your repository:

```bash
# Fork the repository on GitHub first, then:
git clone https://github.com/YOUR-USERNAME/gcp-resource-audit-cleanup.git
cd gcp-resource-audit-cleanup

# Add the upstream repository
git remote add upstream https://github.com/original-owner/gcp-resource-audit-cleanup.git

# Create a new branch for your work
git checkout -b feature/your-feature-name
```

## Development Guidelines

### Code Organization

Our codebase follows a structured organization pattern:

```plaintext
gcp-resource-audit-cleanup/
├── src/
│   ├── core/              # Core functionality
│   │   ├── auth.sh        # Authentication functions
│   │   ├── logging.sh     # Logging utilities
│   │   └── config.sh      # Configuration management
│   ├── resources/         # Resource management
│   │   ├── compute.sh     # Compute Engine functions
│   │   ├── storage.sh     # Cloud Storage functions
│   │   └── network.sh     # Network resource functions
│   └── utils/             # Utility functions
├── tests/                 # Test files
├── docs/                  # Documentation
└── examples/              # Usage examples
```

### Coding Standards

We follow stringent coding standards to maintain code quality and consistency:

Function Design:
```bash
# Good Example
get_instance_metrics() {
    # Function documentation
    local instance_name="$1"  # Document parameters
    local zone="$2"
    
    # Input validation
    if [[ -z "${instance_name}" ]]; then
        log "ERROR" "Instance name is required"
        return 1
    fi
    
    # Core functionality with error handling
    local metrics
    if ! metrics=$(gcloud compute instances describe "${instance_name}" \
        --zone="${zone}" --format="json"); then
        log "ERROR" "Failed to retrieve metrics for ${instance_name}"
        return 1
    fi
    
    echo "${metrics}"
    return 0
}
```

Error Handling:
```bash
# Example of proper error handling
delete_resource() {
    local resource_name="$1"
    local resource_type="$2"
    
    # Acquire resource lock
    if ! acquire_resource_lock "${resource_name}"; then
        log "ERROR" "Failed to acquire lock for ${resource_name}"
        return 1
    fi
    
    # Ensure cleanup happens
    trap 'release_resource_lock "${resource_name}"' EXIT
    
    # Perform operation with proper error checking
    if ! gcloud compute "${resource_type}" delete "${resource_name}" --quiet; then
        log "ERROR" "Failed to delete ${resource_type} ${resource_name}"
        return 1
    fi
    
    log "INFO" "Successfully deleted ${resource_type} ${resource_name}"
    return 0
}
```

### Testing Requirements

We implement several levels of testing:

1. Unit Tests:
```bash
# Example unit test for a function
@test "get_instance_metrics returns valid JSON" {
    # Setup
    local instance_name="test-instance"
    local zone="us-central1-a"
    
    # Execute
    run get_instance_metrics "${instance_name}" "${zone}"
    
    # Verify
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.name')" = "${instance_name}" ]
}
```

2. Integration Tests:
```bash
# Example integration test
@test "full resource cleanup process succeeds" {
    # Setup test environment
    setup_test_resources
    
    # Execute cleanup process
    run cleanup_resources
    
    # Verify results
    [ "$status" -eq 0 ]
    verify_resources_cleaned
}
```

3. Platform-Specific Testing:
Create detailed test reports for your platform:

```bash
#!/bin/bash
# platform_test_report.sh

echo "Platform Test Report"
echo "==================="
echo "OS: $(uname -a)"
echo "Bash Version: ${BASH_VERSION}"
echo "GCloud Version: $(gcloud version | head -n1)"

# Run test suite
./run-tests.sh --comprehensive

# Collect and report results
generate_platform_report
```

## Contribution Workflow

### 1. Creating Changes

When working on a new feature or fix:

```bash
# Create a feature branch
git checkout -b feature/your-feature-name

# Make your changes
# Add tests
# Update documentation

# Verify your changes
shellcheck src/**/*.sh
./run-tests.sh

# Commit with a meaningful message
git commit -m "feature: Add new resource analysis capability

This change adds the ability to analyze resource usage patterns
over time, helping identify optimization opportunities.

- Implements new analysis functions
- Adds comprehensive tests
- Updates documentation
- Fixes #123"
```

### 2. Submitting Changes

Before submitting your pull request:

1. Update documentation to reflect your changes
2. Add or update tests
3. Ensure all tests pass
4. Update the changelog
5. Verify commit messages follow our standards

### 3. Pull Request Review Process

Our review process emphasizes:

- Code quality and standards compliance
- Comprehensive test coverage
- Clear documentation
- Performance implications
- Security considerations

## Release Process

We follow semantic versioning (MAJOR.MINOR.PATCH):

- MAJOR: Breaking changes
- MINOR: New features, backward-compatible
- PATCH: Bug fixes, backward-compatible

For each release:

1. Update version numbers in all relevant files
2. Update CHANGELOG.md with detailed release notes
3. Create a new release branch
4. Tag the release
5. Update documentation

## Getting Help

If you need assistance:

1. Check existing documentation in the `docs/` directory
2. Review closed issues for similar problems
3. Join our community discussions
4. Open a new issue with detailed information

## Recognition

We value all contributions and recognize contributors through:

1. Mentions in release notes
2. Inclusion in our contributors list
3. Acknowledgment in project documentation

Remember, every contribution matters, whether it's code, documentation, testing, or bug reports. Thank you for helping improve GCP Resource Audit & Cleanup!