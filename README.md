# gcp-resource-audit-cleanup

A comprehensive **Bash script** to audit, analyze, and (optionally) **clean up** Google Cloud Platform (GCP) resources that appear **idle** or **unused**. The script supports:

- **Interactive** and **non-interactive** modes  
- A **safe “recommend-only”** mode (lists changes but does not actually perform them)  
- **Test mode** (dry run that validates environment and simulates commands)  
- Detailed **logging**, **error handling**, and **API rate limiting**  
- Resource usage analysis (e.g., idle Compute Engine instances, unused buckets)  
- Service usage listing (displays enabled GCP APIs/services, with placeholders for deeper usage analysis)

> **Version:** 3.2  
> **License:** [MIT License](LICENSE)

---

## Requirements & Assumptions

1. **Bash 4.0+**  
   - The script uses associative arrays and other features available in Bash 4 or higher.  
   - On macOS, the default Bash may be 3.2; consider installing Bash 4 or 5 (e.g., via Homebrew).

2. **Google Cloud SDK**  
   - You must have the [Google Cloud SDK (`gcloud`)](https://cloud.google.com/sdk/docs/install) installed and authenticated.  
   - We recommend **version 350.0.0 or newer** for full compatibility.

3. **IAM Permissions**  
   - To **list** resources, you need viewer roles (e.g., `compute.viewer`, `storage.viewer`).  
   - To **delete** resources or **disable** services, you need corresponding admin roles (e.g., `compute.admin`, `storage.admin`, `serviceusage.serviceUsageAdmin`).  
   - Being a **Project Owner** generally covers all required privileges.

4. **Operating System**  
   - Tested on Linux distributions (Ubuntu, Debian, CentOS) and macOS (with updated Bash).  
   - On Windows, consider using **WSL** (Windows Subsystem for Linux) or **Git Bash** with Bash 4+.

5. **Standard Utilities**  
   - The script assumes typical POSIX utilities (`find`, `gzip`, etc.) are in your system `$PATH`.

---

# gcp-resource-audit-cleanup

A comprehensive **Bash script** to audit, analyze, and (optionally) **clean up** Google Cloud Platform (GCP) resources that appear **idle** or **unused**. The script supports:

- **Interactive** and **non-interactive** modes  
- A **safe “recommend-only”** mode (lists changes but does not actually perform them)  
- **Test mode** (dry run that validates environment and simulates commands)  
- Detailed **logging**, **error handling**, and **API rate limiting**  
- Resource usage analysis (e.g., idle Compute Engine instances, unused buckets)  
- Service usage listing (displays enabled GCP APIs/services, with placeholders for deeper usage analysis)

> **Version:** 3.2  
> **License:** [MIT License](LICENSE)

---

## Requirements & Assumptions

1. **Bash 4.0+**  
   - The script uses associative arrays and other features available in Bash 4 or higher.  
   - On macOS, the default Bash may be 3.2; consider installing Bash 4 or 5 (e.g., via Homebrew).

2. **Google Cloud SDK**  
   - You must have the [Google Cloud SDK (`gcloud`)](https://cloud.google.com/sdk/docs/install) installed and authenticated.  
   - We recommend **version 350.0.0 or newer** for full compatibility.

3. **IAM Permissions**  
   - To **list** resources, you need viewer roles (e.g., `compute.viewer`, `storage.viewer`).  
   - To **delete** resources or **disable** services, you need corresponding admin roles (e.g., `compute.admin`, `storage.admin`, `serviceusage.serviceUsageAdmin`).  
   - Being a **Project Owner** generally covers all required privileges.

4. **Operating System**  
   - Tested on Linux distributions (Ubuntu, Debian, CentOS) and macOS (with updated Bash).  
   - On Windows, consider using **WSL** (Windows Subsystem for Linux) or **Git Bash** with Bash 4+.

5. **Standard Utilities**  
   - The script assumes typical POSIX utilities (`find`, `gzip`, etc.) are in your system `$PATH`.

---

## Installation

1. **Clone the Repository**:

```bash
git clone https://github.com/<YOUR_USERNAME>/gcp-resource-audit-cleanup.git
cd gcp-resource-audit-cleanup
```

2. **Make the Script Executable**:
```bash
chmod +x gcp-resource-audit-cleanup.sh
```

3. **Run the Script in Test Mode**:
```bash
./gcp-resource-audit-cleanup.sh --test
```

## Usage
```bash
./gcp_resource_audit_and_cleanup.sh [OPTIONS] <PROJECT_ID>
```
# Options

| Option                     | Description                                                                                 |
|----------------------------|---------------------------------------------------------------------------------------------|
| `-o, --output-dir DIR`     | Output directory for logs/results (default: `../projects-data`)                            |
| `-d, --days DAYS`          | Days threshold for considering resources idle (default: `30`)                              |
| `-v, --verbose`            | Enable verbose (debug) logging                                                              |
| `-i, --interactive`        | Interactive mode (prompts before deleting resources or disabling services)                 |
| `-r, --recommend-only`     | Only *recommend* deletions or disables; does **not** actually perform them                 |
| `-t, --test-mode`          | Test mode (skips all destructive commands, logs simulated operations, checks environment)  |
| `-h, --help`               | Show usage/help message                                                                     |

---

# Examples

1. **Interactive Mode**:
```bash
./gcp-resource-audit-cleanup.sh --interactive my-project-id
```
2.	**Recommend-Only**:
```bash
./gcp_resource_audit_and_cleanup.sh --recommend-only my-project-id
```
3. **Test Mode**:
```bash
./gcp_resource_audit_and_cleanup.sh --test-mode my-project-id
```
4.	**Combining Flags**:
```bash
./gcp_resource_audit_and_cleanup.sh -r -t -d 60 my-project-id
```
Uses both recommend-only and test mode, with an idle threshold of 60 days.

---

## Contributing
Contributions, suggestions, and feature requests are welcome! Please see [CONTRIBUTING.md] (CONTRIBUTING.md) for more
information on how to get involved, submit issues, or open pull requests.
---

## License
This project is licensed under the [MIT License](LICENSE).
You are free to use, modify, and distribute this software under the terms of that license.
---

## Disclaimer
- **No warranties**: This script is provided *as is*, without warranty of any kind.
- **Production caution**: Always verify resource dependencies and usage in test or recommend-only modes before deleting/
disabling anything in production.
- **Not an official Google product**: This is a community-driven script, not officially supported by Google.

