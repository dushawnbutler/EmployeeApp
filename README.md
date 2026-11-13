# Employee Directory App on AWS with Terraform

A highly available Employee Directory web application deployed on AWS using Terraform.

This project demonstrates Infrastructure as Code, load balancing, Auto Scaling, IAM least-privilege access, S3 object storage, AWS Systems Manager access, application bootstrapping, health checks, and resilience testing.

## Project Overview

The Employee Directory application is deployed behind an Application Load Balancer and runs on EC2 instances managed by an Auto Scaling Group.

Terraform provisions the AWS infrastructure, while EC2 user data bootstraps each instance by installing application dependencies, downloading the Flask application, configuring environment variables, creating a systemd service, and starting the application automatically.

The application is accessible through the Application Load Balancer rather than directly through an EC2 instance.

## Architecture

```text
                         Internet
                            |
                            v
                +------------------------+
                | Application Load       |
                | Balancer (HTTP :80)    |
                +-----------+------------+
                            |
                  Target Group / Health Checks
                            |
               +------------+------------+
               |                         |
               v                         v
        +-------------+           +-------------+
        | EC2 Instance|           | EC2 Instance|
        | Flask App   |           | Flask App   |
        | AZ 1        |           | AZ 2        |
        +------+------+           +------+------+
               |                         |
               +------------+------------+
                            |
                Auto Scaling Group
                  Min: 2
                  Desired: 2
                  Max: 4

          +----------------+   +----------------+
          | Amazon S3      |   | Amazon         |
          | Employee Photos|   | DynamoDB       |
          +----------------+   | Employees data |
                               +----------------+

                            |
                            v
                 AWS Systems Manager
                    Session Manager
```

The VPC spans two Availability Zones in `us-east-2`. Public subnets host the internet-facing ALB and the current EC2 application instances. Private subnets are also provisioned for future architecture improvements such as moving application instances behind a NAT Gateway.

## AWS Services Used

| Service | Purpose |
| --- | --- |
| Amazon VPC | Provides isolated networking for the application |
| Public Subnets | Host the current EC2 application instances and ALB |
| Private Subnets | Reserved for future private-tier architecture |
| Internet Gateway | Provides internet connectivity to public subnets |
| Application Load Balancer | Distributes HTTP traffic across healthy application instances |
| EC2 | Runs the Flask Employee Directory application |
| Auto Scaling Group | Maintains application capacity and replaces unhealthy instances |
| Launch Template | Defines the EC2 AMI, instance type, IAM profile, networking, and bootstrap script |
| Amazon S3 | Stores employee photo objects |
| Amazon DynamoDB | Stores employee records when the database layer is enabled |
| IAM | Provides EC2 access to S3, DynamoDB, and Systems Manager |
| AWS Systems Manager | Provides shell access to instances without relying on direct SSH |
| Amazon SNS | Sends Auto Scaling lifecycle notifications |
| CloudWatch Metrics | Supplies CPU metrics used by target-tracking Auto Scaling |

## Terraform Structure

```text
EmployeeApp/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── terraform.tfvars
├── user-data.sh
└── images/
    └── employee/
        └── my-photo.png
```

`main.tf` contains the AWS infrastructure resources. `variables.tf` defines configurable inputs. `outputs.tf` exposes values such as the ALB URL, VPC ID, S3 bucket name, and Auto Scaling Group name. `versions.tf` defines the Terraform and AWS provider requirements. `user-data.sh` configures each EC2 instance and starts the Flask application.

Terraform state is currently stored locally. Remote state with S3 can be added as a future improvement.

## Networking Design

The application uses a custom VPC with CIDR block:

```text
10.1.0.0/16
```

The environment contains two public subnets and two private subnets distributed across two Availability Zones.

The Application Load Balancer is internet-facing and listens on HTTP port 80. The application security group allows HTTP traffic on port 80 only from the ALB security group.

This ensures users communicate with the load balancer rather than directly with the application instances.

## Application Load Balancer and Auto Scaling

The Application Load Balancer forwards requests to an EC2 target group on port 80.

Target health checks use:

```text
Protocol: HTTP
Path: /
Port: 80
Expected response: 200
```

The Auto Scaling Group uses ELB health checks so that instances that cannot successfully serve the application can be marked unhealthy and replaced.

The intended steady-state configuration is:

```hcl
desired_capacity = 2
min_size         = 2
max_size         = 4
```

Two instances provide application availability across the configured Availability Zones, while the maximum capacity of four allows the group to scale when required.

A target-tracking scaling policy monitors average EC2 CPU utilization with a target value of 60%.

## EC2 Bootstrap

Each EC2 instance is configured automatically through `user-data.sh`.

The bootstrap process installs the required Linux and Python packages, installs and starts the AWS Systems Manager Agent, downloads the Flask Employee Directory application, installs Python dependencies, defines application environment variables, creates a systemd service, starts Flask on port 80, and performs local application health diagnostics.

The application runs as:

```text
python3 -m flask run --host=0.0.0.0 --port=80
```

The systemd service is configured to restart the application automatically if the Flask process exits.

## Bootstrap Issue and Resolution

One of the most important parts of this project was troubleshooting an application bootstrap failure.

Initially, the ALB returned:

```text
502 Bad Gateway
```

The ALB and networking resources were functioning, but no application process was listening on port 80.

The first bootstrap implementation stopped when a Python `pip` upgrade attempted to replace an RPM-managed version of pip. Because the script used strict shell error handling, that failure prevented the rest of the bootstrap process from running.

A later troubleshooting version introduced AWS Systems Manager installation, but SSM startup commands could also stop the bootstrap if the agent was unavailable on the selected Amazon Linux 2023 minimal image.

The final bootstrap was redesigned so that SSM installation is non-blocking while application startup remains strict. The script also waits for the Flask application to return a successful HTTP response before reporting bootstrap success.

This changed the troubleshooting process from repeatedly replacing unhealthy instances to proving each layer independently:

```text
EC2 bootstrap
      |
      v
Flask process listening on :80
      |
      v
Local HTTP 200 response
      |
      v
ALB target health = healthy
      |
      v
Public ALB URL = HTTP 200
```

The final application test returned:

```text
HTTP/1.1 200 OK
Server: Werkzeug
```

confirming that traffic successfully traveled through the ALB to the Flask application.

## IAM Permissions

The EC2 instances use an IAM instance profile rather than static AWS credentials.

The application role provides access required by the workload:

```text
EC2
 ├── S3: GetObject, PutObject, DeleteObject, ListBucket
 ├── DynamoDB: application read/write operations
 └── Systems Manager: AmazonSSMManagedInstanceCore
```

S3 permissions are restricted to the employee photo bucket.

The final DynamoDB configuration should scope permissions to the ARN of the `Employees` table instead of using a wildcard resource. This follows least-privilege principles and prevents the application role from accessing unrelated DynamoDB tables in the AWS account.

## S3 Storage

Amazon S3 is used for employee photo storage.

Terraform creates the bucket and enables S3 Block Public Access. The application IAM role is granted access to the bucket and its objects.

A sample employee image can also be uploaded through Terraform using the configured `photo_source_path`.

The bucket is not intended to be publicly writable. Access is performed through IAM permissions assigned to the EC2 application role.

## DynamoDB

The application runs with DynamoDB mode enabled:

```text
DYNAMO_MODE=on
```

The database design uses an `Employees` DynamoDB table with:

```text
Partition key: id
Type: String
Billing mode: PAY_PER_REQUEST
```

Employee records submitted through the application can be validated from the CLI with:

```bash
aws dynamodb scan \
  --table-name Employees \
  --region us-east-2
```

Using DynamoDB on-demand billing keeps the database configuration simple for a portfolio workload while avoiding the need to pre-provision read and write capacity.

## AWS Systems Manager Access

AWS Systems Manager Session Manager is used to troubleshoot the EC2 instances.

The EC2 IAM role includes:

```text
AmazonSSMManagedInstanceCore
```

Once the SSM Agent is online, an instance can be accessed with:

```bash
aws ssm start-session \
  --target <INSTANCE_ID> \
  --region us-east-2
```

This was used to verify the application service, listening ports, Flask logs, bootstrap logs, and local HTTP responses.

Example troubleshooting commands:

```bash
sudo systemctl status employee-directory.service --no-pager
sudo ss -lntp | grep :80
sudo curl -v http://127.0.0.1:80/
sudo tail -n 100 /var/log/flask.log
sudo tail -n 150 /var/log/user-data.log
```

Using Systems Manager reduces the need to expose SSH access for routine administration.

## Resilience Test

The architecture was tested for more than successful provisioning.

After multiple healthy EC2 instances were running behind the Application Load Balancer, one EC2 instance was manually terminated.

The Auto Scaling Group detected that the number of running instances had fallen below the configured desired capacity and automatically launched a replacement instance.

During the replacement process, the Application Load Balancer continued routing traffic to the remaining healthy target, and the Employee Directory website remained available.

The test demonstrated both:

**High availability** — the website remained accessible while one application instance was unavailable.

**Self-healing infrastructure** — the Auto Scaling Group automatically replaced the terminated instance and restored the desired capacity.

This validation demonstrates the operational value of the architecture rather than simply confirming that Terraform can create AWS resources.

## Deployment Workflow

Initialize the Terraform working directory:

```bash
terraform init
```

Format the configuration:

```bash
terraform fmt
```

Validate the Terraform files:

```bash
terraform validate
```

Review the execution plan:

```bash
terraform plan
```

Deploy the infrastructure:

```bash
terraform apply
```

Retrieve the application URL:

```bash
terraform output -raw alb_url
```

Test the ALB:

```bash
curl -I "$(terraform output -raw alb_url)"
```

A successful deployment should return:

```text
HTTP/1.1 200 OK
```

## Validation Commands

Check Auto Scaling instances:

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-name employee-directory-asg \
  --region us-east-2 \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,AvailabilityZone,LifecycleState,HealthStatus]' \
  --output table
```

Check ALB target health:

```bash
aws elbv2 describe-target-health \
  --target-group-arn <TARGET_GROUP_ARN> \
  --region us-east-2 \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
  --output table
```

Check SSM connectivity:

```bash
aws ssm describe-instance-information \
  --region us-east-2
```

Check DynamoDB records:

```bash
aws dynamodb scan \
  --table-name Employees \
  --region us-east-2
```

## Screenshots

Add the screenshots of the working application to a directory such as:

```text
docs/screenshots/
```

Suggested filenames:

```text
employee-directory-home.png
employee-directory-add-employee.png
alb-targets-healthy.png
asg-resilience-test.png
```

Then add them to this README with:

```markdown
### Employee Directory

![Employee Directory running through the ALB](docs/screenshots/employee-directory-home.png)

### Healthy ALB Targets

![Healthy ALB targets](docs/screenshots/alb-targets-healthy.png)

### Resilience Test

![Auto Scaling Group resilience test](docs/screenshots/asg-resilience-test.png)
```

## Security Considerations

Do not commit AWS credentials, private SSH keys, Terraform state files, or sensitive values to source control.

A `.gitignore` for this project should include:

```gitignore
.terraform/
*.tfstate
*.tfstate.*
.terraform.lock.hcl
terraform.tfvars
*.pem
.DS_Store
```

For a public portfolio repository, sensitive variable values should be supplied through a local `terraform.tfvars`, environment variables, or another secret-management approach rather than hard-coded into tracked Terraform files.

## Key Takeaways

This project demonstrates practical experience with:

- Infrastructure as Code using Terraform
- Multi-AZ AWS networking
- Application Load Balancing
- EC2 Auto Scaling
- Automated EC2 bootstrapping
- Linux systemd service management
- ALB health checks
- IAM least-privilege design
- Amazon S3 object storage
- Amazon DynamoDB
- AWS Systems Manager Session Manager
- Troubleshooting application startup failures
- High-availability and self-healing validation
- Terraform-driven AWS lifecycle management

The most valuable lesson from the project was that successfully provisioning cloud resources is only part of building a working system. The application, instance bootstrap process, IAM permissions, health checks, and recovery behavior all need to work together.

By tracing the failure from the ALB through the target group and down to the EC2 bootstrap process, the application was restored from repeated `502 Bad Gateway` responses to a healthy, load-balanced deployment that successfully returned HTTP `200 OK` and recovered automatically from instance termination.

## Future Improvements

Potential production-oriented improvements include moving EC2 instances into private subnets, adding NAT or VPC endpoints where appropriate, using HTTPS with AWS Certificate Manager, replacing the Flask development server with Gunicorn, storing Terraform state remotely in S3, enabling state locking, adding CI/CD for Terraform validation and deployment, adding CloudWatch dashboards and alarms, and removing temporary SSH access entirely in favor of Systems Manager.

## Cleanup

To remove resources managed by this Terraform configuration:

```bash
terraform destroy
```

Always review the destruction plan carefully before confirming.

---

## Project Status

**Working deployment validated**

- Application reachable through the Application Load Balancer
- ALB returns HTTP `200 OK`
- Flask application running as a systemd service
- EC2 instances managed by an Auto Scaling Group
- SSM Session Manager access validated
- S3 employee photo storage configured
- DynamoDB integration designed for employee records
- Auto Scaling replacement behavior tested
- Website availability maintained during an EC2 termination test
