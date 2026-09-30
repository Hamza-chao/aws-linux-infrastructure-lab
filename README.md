# AWS Linux Infrastructure Lab

Terraform-managed AWS infrastructure demonstrating Linux administration, network
access controls, service recovery, and email alerting. An Amazon Linux 2023 EC2
instance runs Nginx as the workload, with administration through AWS Systems
Manager Session Manager and EC2 health notifications through CloudWatch and SNS.

**Technologies:** AWS EC2, VPC, IAM, Systems Manager, CloudWatch, SNS, EBS,
Terraform, Linux, Bash, Nginx, and Git.

## Architecture and design

- **Networking:** dedicated VPC and public subnet, with an internet gateway and
  route table for internet connectivity.
- **Access:** HTTP restricted to one configured public IPv4 address (`/32`).
  Administration uses Session Manager with no inbound SSH rule.
- **Server:** Amazon Linux 2023 on a `t3.micro`, with an encrypted 8 GiB gp3 root
  volume and IMDSv2 required.
- **Bootstrap:** a Bash startup script installs Nginx and enables Nginx and the
  SSM agent to start automatically.
- **Permissions:** an EC2 instance role provides the SSM agent's AWS permissions.
  Separate deployment policies support Terraform and interactive administration.
- **Monitoring:** a CloudWatch alarm evaluates EC2 `StatusCheckFailed` metrics
  over two one-minute periods. SNS delivers notifications on ALARM and OK transitions.
- **Local health checks:** a Bash script checks Nginx service status and HTTP
  responses, reports disk usage, and returns a status code for the two checks.
- **Cost control:** T3 standard CPU credits, root volume deletion on instance
  termination, and explicit Terraform teardown after use.

## Verified results

| Area | Verification | Observed result |
| --- | --- | --- |
| Provisioning | Applied Terraform configuration | Network, IAM, EC2, and monitoring resources created successfully |
| Remote administration | Connected through Session Manager | Interactive Linux shell without opening inbound SSH |
| HTTP service | Opened the Nginx page and ran `curl -I http://localhost` | HTTP `200 OK` |
| Service recovery | Stopped Nginx, checked HTTP, then restarted it | Connection failure while stopped; HTTP `200 OK` after restart |
| Health-check script | Ran the script with Nginx stopped and then restarted | Both checks failed with exit status `1`, then passed with exit status `0` |
| Linux operations | Inspected service logs, access logs, disk, memory, processes, and listening ports | Confirmed Nginx requests and examined server resource usage |
| Infrastructure lifecycle | Destroyed and recreated the original infrastructure | Terraform reported 10 resources destroyed, then 10 recreated |
| Alert delivery | Confirmed SNS email subscription and temporarily set the alarm to ALARM | Received the alarm notification by email |

The alert test verified the CloudWatch-to-SNS delivery path using a simulated alarm
state. The CloudWatch metric monitors EC2 status checks. The Bash script checks
HTTP locally and reports results in the terminal; it does not send email or run
on a schedule. Lifecycle verification above covers the
original infrastructure before monitoring was added.

## Repository contents

| File | Purpose |
| --- | --- |
| `main.tf` | Infrastructure, server bootstrap, monitoring, inputs, and outputs |
| `lab-health-check.sh` | Nginx service and HTTP checks, disk usage report, and exit status |
| `terraform.tfvars.example` | Example region, allowed IPv4 address, and alert email |
| `lab-access-policy.json` | Deployment and Session Manager permissions |
| `lab-monitoring-policy.json` | Permissions for the lab's SNS topic and CloudWatch alarm |
| `.terraform.lock.hcl` | Pinned provider version and checksums |
| `.gitignore` | Excludes local settings, state, saved plans, and credential files |

## Deployment

Prerequisites: Terraform 1.10 or later (below 2.0), AWS CLI v2, and an authenticated
AWS identity with the lab deployment permissions. Commands below use PowerShell.

The IAM policy files use the lab account ID and `us-east-1`. Adapt their ARNs for
another account. Install these policies using an identity authorized to manage
IAM, and attach them to the deployment user group. The monitoring policy is a
separate customer-managed policy. Deployment identity policies are managed
outside this Terraform configuration.

Copy the example once and edit the local settings:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
(Invoke-RestMethod https://checkip.amazonaws.com).Trim()
```

Set `allowed_http_cidr` to your current public IPv4 address followed by `/32`, and
set `alert_email` to your email address. Update the allowed address if your network
changes. Keep `terraform.tfvars` local.

Authenticate your AWS CLI profile, then validate and review the deployment:

```powershell
$env:AWS_PROFILE = "your-profile-name"
aws sts get-caller-identity
terraform init
terraform fmt -check
terraform validate
terraform plan "-out=lab.tfplan"
```

Review the account, region, and proposed changes before applying:

```powershell
terraform apply "lab.tfplan"
terraform output
```

Allow time for the startup script to install Nginx, then open `website_url` using
HTTP from the permitted address. Confirm the SNS subscription using the email
sent to `alert_email`.

This is a single-instance lab using HTTP and local Terraform state. Its current
scope covers provisioning and operations; it does not provide high availability
or TLS. The AMI follows the latest Amazon Linux 2023 image, so a later plan may
propose instance replacement. Changes to the startup script also replace the instance.

## Operations and recovery

Select the instance in the EC2 console, choose **Connect**, select **SSM Session
Manager**, and connect. Check startup, service status, HTTP, and logs:

```bash
sudo cloud-init status --wait
sudo systemctl status nginx --no-pager
curl -I http://localhost
sudo journalctl -u nginx -n 30 --no-pager
sudo tail -n 10 /var/log/nginx/access.log
```

If installation fails, inspect `/var/log/cloud-init-output.log`. For Session
Manager connection issues, check the instance role, SSM agent, and outbound route.

Reproduce the service recovery test in the lab:

```bash
sudo systemctl stop nginx
curl -I http://localhost
sudo systemctl start nginx
curl -I http://localhost
```

The first HTTP request should fail; the second should return `200 OK`. Recovery
in this test is performed manually using `systemctl`.

Run the health-check script on the EC2 instance after copying
`lab-health-check.sh` from this repository to the Linux user's home directory:

```bash
bash "$HOME/lab-health-check.sh"
echo "Exit status: $?"
```

The script returns `0` when both the service and HTTP checks succeed, or `1`
when either fails. Disk usage is informational; no disk threshold is evaluated.
During the Nginx stop/start test, these statuses were verified as `1` and `0`
respectively. The script currently runs on demand and is copied separately from
Terraform provisioning. Shell files use LF line endings for Linux compatibility.

After confirming the email subscription, test notification delivery from the local
PowerShell terminal using the configured AWS profile:

```powershell
aws cloudwatch set-alarm-state --alarm-name "linux-lab-status-check" --state-value ALARM --state-reason "Testing email notifications" --region us-east-1
```

CloudWatch reevaluates the real metrics after this temporary state change. A return
to OK triggers another notification through the same SNS topic.

## Teardown and costs

EC2 runtime, EBS storage, public IPv4, monitoring, notifications, and data transfer
can incur charges. Resources remain deployed until explicitly removed.

From the same project folder and AWS profile:

```powershell
terraform destroy
terraform state list
```

Confirm successful destruction and check that no managed resources remain in state.
Verify removal of the instance, root volume, VPC, SNS topic, and CloudWatch alarm
in AWS. Stopping the instance alone leaves storage charges. Keep local state until
cleanup succeeds. The separately installed deployment IAM policies remain.

## References

- [Amazon Linux 2023 on EC2](https://docs.aws.amazon.com/linux/al2023/ug/ec2.html)
- [Session Manager setup](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started.html)
- [CloudWatch alarm notification testing](https://docs.aws.amazon.com/cli/latest/reference/cloudwatch/set-alarm-state.html)
- [EC2 pricing](https://aws.amazon.com/ec2/pricing/on-demand/), [EBS pricing](https://aws.amazon.com/ebs/pricing/), and [public IPv4 pricing](https://aws.amazon.com/vpc/pricing/)
