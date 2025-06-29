# Palo Alto VM-Series Deployment on AWS using Terraform

This Terraform configuration deploys a Palo Alto VM-Series firewall solution in AWS. It automates the setup of a VPC with subnets, security groups, S3-based bootstrapping, EC2 instances running PAN-OS, and integration with a Gateway Load Balancer (GWLB).

---

## 🧰 Components Deployed

1. **AWS Provider** configuration
2. **VPC** with IPAM-based CIDR assignment (via `aws-ia/vpc` module)
3. **Subnets**: Public, Private, and Management
4. **Security Group** for Management Access (SSH & SNMP)
5. **AMI lookup** for Palo Alto PAN-OS
6. **S3 Bucket** for bootstrapping Palo Alto instances
7. **Two EC2 Instances** running Palo Alto VM-Series
8. **Gateway Load Balancer (GWLB)** with target group attachments
9. **VPC Endpoint Service** for GWLB exposure

