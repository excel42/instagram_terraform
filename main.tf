provider "aws" {
  region = var.aws_region
}

# VPC 및 서브넷
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_a_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_c_cidr
  availability_zone       = "${var.aws_region}c"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "c" {
  subnet_id      = aws_subnet.public_c.id
  route_table_id = aws_route_table.public.id
}

# 정적 웹사이트용 S3
resource "aws_s3_bucket" "static_web" {
  bucket = var.static_web_bucket
}

resource "aws_s3_bucket_website_configuration" "static_web_website" {
  bucket = aws_s3_bucket.static_web.id
  index_document {
    suffix = "index.html"
  }
  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_public_access_block" "static_web" {
  bucket = aws_s3_bucket.static_web.id
  block_public_acls   = false
  block_public_policy = false
  ignore_public_acls  = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "static_web_policy" {
  bucket = aws_s3_bucket.static_web.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "PublicReadGetObject",
      Effect    = "Allow",
      Principal = "*",
      Action    = ["s3:GetObject"],
      Resource  = ["${aws_s3_bucket.static_web.arn}/*"]
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.static_web]
}

# 이미지 버킷 (image_storage)
resource "aws_s3_bucket" "image_storage" {
  bucket = var.image_storage_bucket
}

resource "aws_s3_bucket_public_access_block" "image_storage" {
  bucket = aws_s3_bucket.image_storage.id
  block_public_acls   = false
  block_public_policy = false
  ignore_public_acls  = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_versioning" "image_storage_versioning" {
  bucket = aws_s3_bucket.image_storage.id
  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_policy" "image_storage_policy" {
  bucket = aws_s3_bucket.image_storage.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "PublicReadGetObject",
      Effect    = "Allow",
      Principal = "*",
      Action    = ["s3:GetObject"],
      Resource  = ["${aws_s3_bucket.image_storage.arn}/*"]
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.image_storage]
}

# CloudFront
resource "aws_cloudfront_distribution" "web_cdn" {
  origin {
    domain_name = aws_s3_bucket.static_web.bucket_regional_domain_name
    origin_id   = "s3-static-web"
  }
  enabled             = true
  default_root_object = "index.html"
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-static-web"
    viewer_protocol_policy = "redirect-to-https"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  price_class = "PriceClass_200"
}

# RDS(MySQL)
resource "aws_db_subnet_group" "rds_subnet" {
  name       = "instagram-db-subnet"
  subnet_ids = [aws_subnet.public_a.id, aws_subnet.public_c.id]
}

resource "aws_security_group" "ec2_sg" {
  name   = "ec2-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 운영시 본인IP만!
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
    ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name   = "rds-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "instagram_db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0.40"
  instance_class       = "db.t3.micro"
  db_name              = var.db_name
  username             = var.db_username
  password             = var.db_password
  publicly_accessible  = true 
  skip_final_snapshot  = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet.name
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"
}

# EC2 인스턴스 
resource "aws_instance" "backend" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = <<-EOF
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y openjdk-17-jdk git unzip

cd /home/ubuntu
git clone ${var.backend_git_repo}
cd aws-final-springboot

# gradle wrapper build
if [ -f ./gradlew ]; then
  chmod +x ./gradlew
  ./gradlew build -x test
else
  apt install -y gradle
  gradle build -x test
fi

# application.yml 생성 (DB 연결정보)
cat > src/main/resources/application.yml <<EOL
spring:
  datasource:
    url: jdbc:mysql://${aws_db_instance.instagram_db.address}:3306/${var.db_name}
    username: ${var.db_username}
    password: ${var.db_password}
  jpa:
    hibernate:
      ddl-auto: update
    show-sql: true
  cloud:
aws:
  s3:
    bucket: ${var.image_storage_bucket}
EOL

# jar 파일 실행
JAR_FILE=$(find build/libs -name "*.jar" | head -n 1)
if [ -n "$JAR_FILE" ]; then
  nohup java -jar $JAR_FILE --spring.profiles.active=prod > /home/ubuntu/springboot.log 2>&1 &
fi
EOF

  tags = { Name = "prod-instagram-server" }
}

# ALB (Application Load Balancer)
resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "alb" {
  name               = "prod-instagram-elb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_c.id]
}

resource "aws_lb_target_group" "alb_tg" {
  name     = "alb-tg"
  port     = 8080 # Spring Boot 
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path    = "/health"
    matcher = "200"
  }
}

resource "aws_lb_listener" "alb_http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "ec2_attach" {
  target_group_arn = aws_lb_target_group.alb_tg.arn
  target_id        = aws_instance.backend.id
  port             = 8080
}
