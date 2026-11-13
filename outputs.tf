output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.app.dns_name
}

output "alb_url" {
  description = "URL to access the Employee Directory App"
  value       = "http://${aws_lb.app.dns_name}"
}

output "s3_bucket_name" {
  description = "Name of the employee photos S3 bucket"
  value       = aws_s3_bucket.photos.bucket
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.app.name
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.app.id
}
