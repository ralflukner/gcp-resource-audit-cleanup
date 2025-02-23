# GCP Resource Audit and Cleanup

The GCP Resource Audit and Cleanup tool is a sophisticated Bash script designed to help system administrators and cloud engineers maintain their Google Cloud Platform environments. This tool systematically analyzes resource usage patterns, identifies optimization opportunities, and safely manages resource lifecycle, all while maintaining strict safety controls and comprehensive audit trails.

## Key Features

The script provides a robust set of capabilities for GCP resource management:

Resource Analysis:
- Compute Engine instance utilization patterns and optimization opportunities
- Storage bucket access patterns and lifecycle management
- Unattached persistent disk identification
- Snapshot retention analysis and cleanup recommendations
- Network resource utilization assessment

Safety and Control:
- Interactive and non-interactive operation modes
- Comprehensive dependency checking before any resource modification
- Rate-limited API calls to prevent quota exhaustion
- Detailed logging and audit trails
- Resource locking to prevent concurrent modifications

Performance Optimization:
- Efficient batch processing of resource inventories
- Intelligent retry mechanisms with exponential backoff
- Parallel processing capabilities where appropriate
- Memory-efficient handling of large resource sets

## Version and Compatibility

Current Version: 3.2.4
Release Date: January 2025

The script has been thoroughly tested in the following environments:
- Linux: Ubuntu 22.04+, Debian 11+, Red Hat Enterprise Linux 8+
- macOS: Ventura (13.0) and later with Bash 4.0+ installed
- Windows: Windows Subsystem for Linux 2 (WSL2) with Ubuntu 22.04

## Prerequisites

Before using this tool, ensure your environment meets these requirements:

1. Bash Environment:
   - Bash version 4.0 or higher is required
   - For macOS users: Install updated Bash via Homebrew:
     ```bash
     brew install bash
     ```

2. Google Cloud SDK:
   - Minimum version: 350.0.0
   - Installation guide: https://cloud.google.com/sdk/docs/install
   - Must be properly authenticated with sufficient permissions

3. Required System Utilities:
   - jq (JSON processor)
   - gcloud (Google Cloud SDK)
   - awk
   - curl
   - mktemp

4. IAM Permissions:
   For read-only analysis:
   - roles/compute.viewer
   - roles/storage.viewer
   - roles/monitoring.viewer

   For resource management:
   - roles/compute.admin
   - roles/storage.admin
   - roles/monitoring.admin

## Installation

1. cClone the repository:
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

The script supports various operation modes and configuration options:

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

## Output and Reports

The script generates several types of output:

1. Resource Inventory:
   - Comprehensive listing of all GCP resources
   - Usage patterns and statistics
   - Dependency mappings

2. Analysis Reports:
   - Resource utilization metrics
   - Cost optimization opportunities
   - Security recommendations

3. Audit Logs:
   - Detailed operation logs
   - Error reports and warnings
   - Action audit trails

All outputs are stored in the specified output directory with timestamps and proper categorization.

## Safety Features

The script implements multiple safety mechanisms:

1. Resource Locking:
   - Prevents concurrent modifications
   - Ensures atomic operations
   - Automatic lock cleanup

2. Dependency Checking:
   - Full dependency graph analysis
   - Cascade impact assessment
   - Automatic abort for unsafe operations

3. Rate Limiting:
   - Token bucket algorithm
   - Configurable rate limits
   - Automatic backoff on API throttling

## Troubleshooting

Common issues and their solutions:

1. Authentication Errors:
   - Run `gcloud auth login`
   - Verify project permissions
   - Check credential expiration

2. Rate Limiting:
   - Adjust API_CALLS_PER_MINUTE in script
   - Monitor quota usage
   - Implement request batching

3. Permission Issues:
   - Verify IAM roles
   - Check project access
   - Review audit logs

## Contributing

We welcome contributions to improve this tool:

1. Fork the repository
2. Create a feature branch
3. Implement improvements
4. Add tests
5. Submit a pull request

Please review our contributing guidelines for more details.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Security Considerations

While this script implements numerous safety checks, users should:
- Always test in non-production environments first
- Maintain proper backup procedures
- Review all recommended actions before execution
- Monitor audit logs for unexpected behavior

## Support and Contact

For issues, feature requests, or contributions:
- Open an issue in the GitHub repository
- Submit pull requests for improvements
- Contact the maintainers directly

Remember to include relevant logs and environment details when reporting issues.
