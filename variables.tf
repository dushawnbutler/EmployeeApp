variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Project name used for tagging and naming"
  type        = string
  default     = "employee-directory"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "ssh_public_key" {
  description = "SSH public key content (do NOT commit private keys)"
  type        = string
  default     = // Add SSH key

variable "key_name" {
  description = "Name of the EC2 key pair"
  type        = string
  default     = "app-key-pair"
}

variable "ami_id" {
  description = "AMI ID (Amazon Linux 2 recommended)"
  type        = string
  default     = "ami-00216c5abd290d24d"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "photos_bucket_name" {
  description = "Globally unique S3 bucket name for employee photos"
  type        = string
  default     = "employee-photo-bucket-sb-26"
}

variable "sns_email" {
  description = "Email address for ASG notifications"
  type        = string
  default     = // Add email to receive SNS notifications
}

variable "photo_source_path" {
  description = "Relative path to the employee photo inside the project"
  type        = string
  default     = // Add filepath to retrieve photos for the directory when adding employees. 
} 
