# AWS Linux Infrastructure Lab

Learn to provision, administer, troubleshoot, and recover a Linux server on AWS.
The workload is Nginx's default welcome page. There is no custom web application.

**First milestone:** create one server, inspect it, stop and recover its web service,
then remove the environment. Deployment, Session Manager access, Nginx recovery,
and destruction/recreation have been exercised on AWS. CloudWatch-to-SNS email
delivery has also been tested using a temporary alarm state change.

## Start here

Read the network and server sections in `main.tf`. The first exercise needs only
Terraform, AWS CLI authentication, and an AWS account. The lab now includes an
EC2 status-check alarm and SNS email notifications. Backups, Ansible, and CI/CD
are possible later exercises.

| File | Purpose |
| --- | --- |
| `main.tf` | Settings, network, server permissions, Linux server, and Nginx installation |
| `terraform.tfvars.example` | Example region, browser access, and alert email settings |
| `lab-access-policy.json` | Deployment and Session Manager permissions |
| `lab-monitoring-policy.json` | Permissions to manage the lab alarm and SNS topic |
| `.gitignore` | Keeps local settings, Terraform state, and credentials out of Git |
| `.terraform.lock.hcl` | Generated provider version/checksums; keep this in Git |

The traffic path is: your browser -> public IPv4 -> security group -> Nginx on port 80.
The server sits in one public subnet in its own VPC. An internet gateway and route
give it outbound connectivity for package installation and AWS Systems Manager.
Administration uses Session Manager; no SSH key or inbound SSH rule is required.

## Prepare and check locally

Use PowerShell from this project folder. Install Terraform 1.10+ (below 2.0) and
AWS CLI v2. The following checks download the provider but create no AWS resources:

```powershell
terraform init
terraform fmt -check
terraform validate
```

Copy settings once, then edit `terraform.tfvars`:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
(Invoke-RestMethod https://checkip.amazonaws.com).Trim()
```

Put the returned public IPv4 address followed by `/32` in `allowed_http_cidr`.
The example `203.0.113.10` is a placeholder. Keep `/32`: it permits only your address.
If your network or VPN changes your public IP, update this setting and apply again.
Set `alert_email` to your email address. Keep `terraform.tfvars` out of Git.

Use your configured AWS CLI profile. For a named profile, set
`$env:AWS_PROFILE = "your-profile-name"` in this terminal. For an IAM Identity Center
profile, authenticate with `aws sso login`. Verify the intended account:

```powershell
aws sts get-caller-identity
```

Your deployment identity needs permissions to manage the lab's EC2/VPC and IAM
resources, pass its instance role, and read the public SSM AMI parameter. Your
console identity also needs permission to start Session Manager sessions. The
instance role in `main.tf` grants permissions to the server, not to your user.
Keep AWS credentials in the CLI configuration, outside this repository.

The two policy JSON files record the permissions used in this lab. Their ARNs
contain the lab account ID and use `us-east-1`; adapt those values for another
account. Attach the monitoring policy as a separate customer-managed policy to
the deployment user group. These IAM policies are installed separately from
Terraform and remain after `terraform destroy`.

## Deploy when ready

Applying creates billable resources: a `t3.micro`, an 8 GiB EBS disk, and a public
IPv4 address. CloudWatch alarms, SNS usage, and data transfer can also cost money. Check your account's pricing and
credits first. This milestone has **manual teardown**, with no automatic expiry.

```powershell
terraform plan "-out=lab.tfplan"
```

Review the account, region, and proposed resources. When ready to create them:

```powershell
terraform apply "lab.tfplan"
terraform output
```

Give first boot several minutes to install Nginx. Open `website_url` using **HTTP**;
TLS is not configured for this initial exercise. Terraform finishing does not prove
Nginx is ready. The image follows the latest Amazon Linux 2023 release; a later
plan may propose replacing the server. Changes to the boot script also replace it.

## Operate the server

In the AWS EC2 console, select the output `instance_id` in your configured region,
then choose **Connect -> Session Manager -> Connect**. Run these Linux commands:

```bash
sudo cloud-init status --wait
sudo systemctl status nginx --no-pager
curl -I http://localhost
sudo journalctl -u nginx -n 30 --no-pager
```

Check `sudo tail -n 50 /var/log/cloud-init-output.log` if installation failed.
If Session Manager is unavailable, allow time for registration and check the
instance role, internet route, and your session permissions.

For the first failure exercise, run `sudo systemctl stop nginx`. Confirm that
`curl -I http://localhost` and a fresh browser request fail. Inspect service status
and logs, then run `sudo systemctl start nginx` and verify HTTP works again.
This is manual detection and recovery. The EC2 status-check alarm does not detect
Nginx stopping; it monitors instance health, not HTTP availability.

## Test email notifications

After applying, confirm the SNS subscription using the link sent to `alert_email`.
Then run this in your local PowerShell terminal, using your configured AWS profile:

```powershell
aws cloudwatch set-alarm-state --alarm-name "linux-lab-status-check" --state-value ALARM --state-reason "Testing email notifications" --region us-east-1
```

This temporarily changes the alarm state and tests notification delivery without
causing a server failure. CloudWatch reevaluates the real metrics and returns to
OK if healthy, sending another notification. An ALARM email was received during
this exercise; detecting an actual EC2 status-check failure has not been tested.

## Remove the environment

Run from this same project folder with the same AWS profile and local settings:

```powershell
terraform destroy
terraform state list
```

Review the destruction plan and confirm it. The state list should then be empty.
In the same AWS region, verify the lab instance is terminated, its root disk is
gone, and the `linux-lab` VPC is gone. Stopping the instance alone leaves storage
charges. Keep the local state files until destruction succeeds; if apply fails
partway through, use the same state to finish cleanup.

## Milestone checklist

- [x] Terraform created the environment in my intended account.
- [x] I opened the default Nginx page and connected through Session Manager.
- [ ] I can explain the browser traffic path and the purpose of the instance role.
- [x] I stopped Nginx, inspected the failure, and restored the service.
- [x] I recorded the exercises and commands in this README.
- [x] I confirmed the SNS subscription and received a test ALARM email.
- [x] Terraform reported all 10 original resources destroyed; I then recreated them.
- [ ] I verified teardown of the expanded lab including SNS and CloudWatch.

## References

- [Amazon Linux 2023 images and the public AMI parameter](https://docs.aws.amazon.com/linux/al2023/ug/ec2.html)
- [Session Manager setup and permissions](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started.html)
- [EC2 pricing](https://aws.amazon.com/ec2/pricing/on-demand/), [EBS pricing](https://aws.amazon.com/ebs/pricing/), and [public IPv4 pricing](https://aws.amazon.com/vpc/pricing/)
