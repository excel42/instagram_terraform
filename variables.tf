variable "aws_region" {
  description = "AWS region"
  default     = "ap-northeast-2"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "subnet_a_cidr" {
  default = "10.0.1.0/24"
}
variable "subnet_c_cidr" {
  default = "10.0.2.0/24"
}

variable "static_web_bucket" {
  description = "S3 bucket for static website"
  default     = "myinsta-static-web-bucket-29847891"
}

variable "image_storage_bucket" {
  description = "S3 bucket for images"
  default     = "myinsta-image-storage-bucket-322786782"
}

variable "db_username" {
  description = "RDS admin username"
  default     = "adminuser"
}

variable "db_password" {
  description = "RDS admin password"
  sensitive   = true
}

variable "db_name" {
  default = "instagram"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0ec5bcf6f13821b27"
}

variable "backend_git_repo" {
  default = "https://github.com/JSCODE-BOOK/aws-final-springboot.git"
}
