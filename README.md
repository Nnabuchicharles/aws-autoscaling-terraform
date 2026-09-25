# AWS Auto Scaling Infrastructure with Terraform

A hands-on AWS infrastructure project that provisions a load-balanced, auto-scaling web tier using Terraform. The design places an internet-facing Application Load Balancer in public subnets and EC2 instances in private subnets across two Availability Zones. CloudWatch CPU alarms trigger step scaling policies that add or remove EC2 capacity.

## Project goals

- Provision AWS networking and compute infrastructure with Terraform.
- Distribute HTTP traffic through an Application Load Balancer (ALB).
- Keep application EC2 instances in private subnets rather than exposing them directly to the internet.
- Run the web tier across two Availability Zones through an Auto Scaling Group.
- Scale out when average EC2 CPU utilization is at least 50% and scale in when it is at most 20%.
- Use IAM instance profiles for AWS Systems Manager and CloudWatch access.

## Architecture implemented

The implementation creates a `10.0.0.0/16` VPC with two public and two private subnets across the first two available Availability Zones in `us-east-1`.

```text
Internet
   |
Internet Gateway
   |
Application Load Balancer
(public subnets across 2 AZs)
   |
Target Group / HTTP health checks
   |
Auto Scaling Group (min 1 / desired 1 / max 6)
   |
EC2 instances in private subnets across 2 AZs
   |
NAT Gateway for outbound internet access

CloudWatch CPU alarms ---> scale-out / scale-in policies
IAM instance profile ---> SSM + CloudWatch permissions
```

> An architecture image can be added under `docs/architecture/` and embedded here later.

## AWS services and tools

**AWS:** VPC, EC2, Application Load Balancer, Auto Scaling, CloudWatch, IAM, Systems Manager, NAT Gateway, Elastic IP

**Infrastructure as Code:** Terraform

**Web server:** Apache on Ubuntu 22.04 LTS

## Repository structure

```text
aws-autoscaling-terraform/
├── README.md
├── .gitignore
├── terraform/
│   ├── .terraform.lock.hcl
│   ├── provider.tf
│   ├── networking.tf
│   ├── security.tf
│   ├── iam.tf
│   ├── launch-template.tf
│   ├── alb.tf
│   ├── autoscaling.tf
│   └── outputs.tf
└── docs/
    ├── architecture/
    └── screenshots/
```

## Networking design

Terraform creates:

- VPC: `10.0.0.0/16`
- Public subnet A: `10.0.1.0/24`
- Public subnet B: `10.0.2.0/24`
- Private subnet A: `10.0.3.0/24`
- Private subnet B: `10.0.4.0/24`
- Internet Gateway for public-subnet internet connectivity
- One NAT Gateway in public subnet A for outbound traffic from both private subnets
- Public and private route tables

The ALB is deployed across both public subnets. The Auto Scaling Group launches EC2 instances across both private subnets.

## Security design

The ALB security group accepts HTTP traffic on port 80 from the internet. The EC2 security group accepts port 80 **only from the ALB security group**, so the application instances are not directly exposed to inbound internet traffic.

No SSH ingress rule is configured. The EC2 IAM role includes `AmazonSSMManagedInstanceCore`, enabling Systems Manager-based administration when the required agent/connectivity is available. It also includes `CloudWatchAgentServerPolicy`.

## Launch template

The launch template retrieves the current Ubuntu 22.04 LTS AMI ID through AWS Systems Manager Parameter Store and launches `t3.micro` instances. User data installs Apache, writes a simple test page, enables Apache, and starts the service.

## Load balancing and health checks

The Application Load Balancer listens on HTTP port 80 and forwards requests to an instance target group. The target group performs HTTP health checks against `/` every 30 seconds and expects an HTTP `200` response.

The Auto Scaling Group uses ELB health checks with a 120-second grace period, allowing unhealthy instances to be identified and replaced through the group lifecycle.

## Auto Scaling behavior

The Auto Scaling Group is configured with:

| Setting | Value |
| --- | ---: |
| Minimum capacity | 1 |
| Desired capacity | 1 |
| Maximum capacity | 6 |

Two CloudWatch alarms drive scaling:

- **Scale out:** average EC2 CPU utilization `>= 50%` for two 60-second evaluation periods. The scaling policy adds one instance and uses a 120-second cooldown.
- **Scale in:** average EC2 CPU utilization `<= 20%` for three 60-second evaluation periods. The scaling policy removes one instance and uses a 180-second cooldown.

## Deploying the infrastructure

### Prerequisites

- Terraform 1.5+
- AWS CLI configured with credentials for an AWS account
- Permissions to create the AWS resources defined in this repository

From the `terraform` directory:

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

After deployment, Terraform outputs the public DNS name of the Application Load Balancer:

```bash
terraform output alb_dns_name
```

Open that DNS name in a browser to reach the Apache test page through the ALB.

## Validation performed

The project is designed to validate several infrastructure behaviors:

1. Requests reach the ALB and are forwarded only to healthy EC2 targets.
2. EC2 instances run in private subnets and receive application traffic from the ALB security group.
3. CPU utilization can trigger the CloudWatch scale-out alarm and increase Auto Scaling Group capacity.
4. Low CPU utilization can trigger scale-in while respecting the configured minimum capacity.
5. The Auto Scaling Group can launch replacement instances from the launch template.

## Production improvements

This repository represents the implemented learning project. For a production workload, I would consider several improvements rather than treating the current configuration as production-complete:

- Add HTTPS with an ACM certificate and redirect HTTP to HTTPS.
- Use one NAT Gateway per Availability Zone, or evaluate VPC endpoints/other egress designs, to reduce the current single-NAT dependency.
- Replace simple step scaling with an appropriate target-tracking policy where workload behavior supports it.
- Add application-specific health endpoints instead of relying only on `/`.
- Add centralized application/system logging and explicitly configure the CloudWatch Agent if detailed host logs/metrics are required.
- Add remote Terraform state with locking and encryption for team workflows.
- Add CI checks for `terraform fmt`, `terraform validate`, linting, and security scanning.
- Add tighter IAM permissions instead of relying solely on AWS-managed policies where least-privilege requirements demand it.

## What I learned

This project demonstrates how load balancing, private networking, health checks, Auto Scaling, CloudWatch alarms, IAM, and Infrastructure as Code work together to build an elastic AWS web tier. It also highlights the distinction between making EC2 instances horizontally scalable and designing every supporting dependency for high availability.
