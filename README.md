# GCP Resource Audit and Cleanup

The GCP Resource Audit and Cleanup tool provides a sophisticated, safety-focused approach to managing Google Cloud Platform environments. Version 3.2.7 introduces significant enhancements to system reliability, error handling, and cross-platform compatibility, while maintaining our commitment to secure and predictable resource management.

## Key Features

The system provides comprehensive capabilities for GCP resource management:

Resource Analysis:
Our enhanced analysis system now provides more reliable detection of resource utilization patterns, optimization opportunities, and potential security concerns. The system examines compute instances, storage resources, and network configurations through multiple validation layers to ensure accurate results.

Safety and Control:
Version 3.2.7 introduces sophisticated error handling and state management, providing enhanced protection against concurrent modifications and improved recovery from unexpected conditions. Our new permission model implements precise access controls following the principle of least privilege.

Performance and Reliability:
The improved core utilities provide robust error recovery, efficient batch processing, and intelligent retry mechanisms. Our enhanced locking system prevents resource conflicts while maintaining system responsiveness.

## Version and Compatibility

Current Version: 3.2.7
Release Date: February 2025

Environment Compatibility:
- Linux: Ubuntu 22.04+, Debian 11+, Red Hat Enterprise Linux 8+
- macOS: Ventura (13.0) and later with Bash 4.0+
- Windows: Windows Subsystem for Linux 2 (WSL2) with Ubuntu 22.04

## Prerequisites

System Requirements:

1. Bash Environment:
   - Bash version 4.0 or higher (required)
   - For macOS users: Install updated Bash via Homebrew:
     ```bash
     brew install bash
     ```

2. Google Cloud SDK:
   - Minimum version: 458.0.1
   - Installation guide: https://cloud.google.com/sdk/docs/install
   - Must be authenticated with appropriate permissions

3. Required System Utilities:
   - jq: JSON processor
   - gcloud: Google Cloud SDK
   - awk: Text processing
   - curl: Data transfer
   - mktemp: Temporary file management

4. IAM Permissions:
   For analysis operations:
   - roles/compute.viewer
   - roles/storage.viewer
   - roles/monitoring.viewer

   For resource management:
   - roles/compute.admin
   - roles/storage.admin
   - roles/monitoring.admin

## Installation

1. Clone the repository:
```bash
git clone https://github.com/your-username/gcp-resource-audit-cleanup.git
cd gcp-resource-audit-cleanup
```

2. Make the script executable:
```bash
chmod +x gcp-resource-audit-cleanup.sh
```

3. Verify your environment:
```bash
./gcp-resource-audit-cleanup.sh --test
```

## Usage Guide

The script supports various operation modes with enhanced safety controls:

Basic Usage:
```bash
./gcp-resource-audit-cleanup.sh --project-id PROJECT_ID [OPTIONS]
```

Available Options:
```
--project-id      GCP Project ID (required)
--verbose         Enable detailed logging
--interactive     Enable interactive mode for confirmations
--output-format   Output format (text|json)
--days-idle      Days threshold for resource idleness
--output-dir     Directory for output files
--test           Run in test mode without making changes
```

Common Usage Patterns:

1. Safe Analysis Mode:
```bash
./gcp-resource-audit-cleanup.sh \
  --project-id your-project \
  --output-format json \
  --verbose
```

2. Interactive Cleanup:
```bash
./gcp-resource-audit-cleanup.sh \
  --project-id your-project \
  --interactive \
  --days-idle 45
```

3. Automated Audit:
```bash
./gcp-resource-audit-cleanup.sh \
  --project-id your-project \
  --output-dir /path/to/reports \
  --output-format json
```

## Safety Features

Version 3.2.7 introduces enhanced safety mechanisms:

1. Resource Locking:
   - Distributed lock management
   - Automatic deadlock prevention
   - Lock inheritance tracking
   - Stale lock cleanup

2. State Management:
   - Pre-update state validation
   - Automatic backup creation
   - Atomic write operations
   - Corruption detection and recovery

3. Error Handling:
   - Comprehensive error codes
   - Stack trace generation
   - State capture for debugging
   - Specialized recovery procedures

## Output and Reports

The system generates detailed reports including:

1. Resource Inventory:
   - Comprehensive resource listings
   - Usage pattern analysis
   - Dependency mapping

2. Analysis Reports:
   - Resource utilization metrics
   - Cost optimization recommendations
   - Security assessment findings

3. Audit Logs:
   - Detailed operation records
   - Error reports and resolutions
   - Complete action audit trails

## Troubleshooting

Common issues and solutions:

1. Authentication Errors:
   - Run `gcloud auth login`
   - Verify project permissions
   - Check credential expiration

2. Rate Limiting:
   - Monitor quota usage
   - Implement request batching
   - Adjust API_CALLS_PER_MINUTE

3. Permission Issues:
   - Verify IAM roles
   - Check project access
   - Review audit logs

## Contributing

We welcome contributions that enhance system reliability and safety:

1. Fork the repository
2. Create a feature branch
3. Implement improvements
4. Add tests
5. Submit a pull request

Please review our contributing guidelines for more details.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Security Considerations

The system implements numerous safety checks. Users should:
- Test in non-production environments first
- Maintain proper backup procedures
- Review all recommended actions
- Monitor audit logs for unexpected behavior

## Support and Contact

For issues, feature requests, or contributions:
- Open an issue in the GitHub repository
- Submit pull requests for improvements
- Contact the maintainers directly

Remember to include relevant logs and environment details when reporting issues.