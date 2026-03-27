# Enterprise Multi-Cloud Endpoint Management Automation

This repository provides a production-ready, highly parameterized, and scalable infrastructure-as-code and configuration management solution. It is designed to deploy and patch Windows, macOS, and Mobile devices across multi-cloud environments (AWS, Azure, GCP) utilizing Terraform and Ansible.

## Architecture Highlights

### 1. Multi-Cloud Infrastructure via Terraform
The `terraform/` directory has been refactored into distinct modules (`aws`, `azure`, `gcp`), preparing the codebase for multi-cloud deployments.
- **Remote State Support:** Configuration templates exist in `backend.tf` for S3 (with DynamoDB locking), Azure Storage, and GCS.
- **Extensibility:** The modular approach ensures easy additions of specific enterprise cloud constructs (VPCs, Security Groups, IAM Roles).

### 2. Role-Based Ansible Automation (Multi-EDR, Multi-MDM)
The Ansible automation relies on modular `roles/` executed by a master orchestration playbook (`site.yml`), offering dynamic and parameterized deployments based on the `enterprise_vars.yml` configuration.
- **Dynamic Inventory:** Ready-to-use plugins are configured (`aws_ec2.yml`, `azure_rm.yml`, `gcp_compute.yml`) to automatically resolve endpoint IPs from cloud environments.
- **Parameterized EDR Deployments:** Deploying CrowdStrike, SentinelOne, or natively managing Windows Defender is entirely dependent on changing the `edr_solution` variable in `enterprise_vars.yml`.
- **API-Driven MDM Integration:** Mobile device management logic triggers sync operations via APIs from enterprise solutions such as Microsoft Intune and Jamf Pro based on the `mdm_solution` variable.

## Setup & Deployment Instructions

### Credentials & Requirements
- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.0.0
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) >= 2.9
- Ensure cloud authentication occurs via robust secret mechanisms (e.g., Azure SPNs, AWS IAM Roles/OIDC).
- Set Environment Variables for EDR and MDM tokens to keep secrets out of git. (e.g., `export CS_FALCON_CID="your-cid"`, `export INTUNE_API_TOKEN="token"`)

### Infrastructure Provisioning
Navigate to your specific cloud module, configure variables and run:
```bash
cd terraform/modules/aws
terraform init
terraform apply
```

### Configuration & Policy Execution

Edit `ansible/enterprise_vars.yml` to specify which EDR or MDM you wish to deploy.
Execute the entire enterprise run via the master site playbook using dynamic inventory:
```bash
cd ansible

# Example targeting AWS dynamic inventory
ansible-playbook -i inventory/aws_ec2.yml site.yml
```