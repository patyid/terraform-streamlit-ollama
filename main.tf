terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
  backend "s3" {
    bucket         = "terraform-backend-bucket-452271769418"
    key            = "state/streamlit-ollama-project.tfstate"
    region         =  "us-east-1"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}

# VPC default e subnet pública automática
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  
  filter {
    name   = "availability-zone"
    values = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1f"]
  }
}

locals {
  subnet_id = data.aws_subnets.default.ids[0]
}

# AMI Deep Learning GPU-ready
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  
  filter {
    name   = "state"
    values = ["available"]
  }
}

# IAM Role para SSM (facilita acesso sem SSH)
resource "aws_iam_role" "ssm_role" {
  name = "streamlit-ollama-ssm-role-v1"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "streamlit-ollama-ssm-profile-v1"
  role = aws_iam_role.ssm_role.name
}

# Security Group: Streamlit + egress para SSM
resource "aws_security_group" "stream_sg" {
  name        = "streamlit-sg"
  description = "Allow Streamlit access and SSM egress"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 8501
    to_port     = 8501
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Spot Instance (usando aws_instance com spot options)
resource "aws_instance" "cpu_spot" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  associate_public_ip_address = true
  vpc_security_group_ids = [aws_security_group.stream_sg.id]
  subnet_id              = local.subnet_id

  root_block_device {
    volume_size = 20    # Tamanho em GB (8GB é o padrão, mude para 20 ou 30)
    volume_type = "gp3" # Tipo mais moderno e barato que gp2
    encrypted   = true  # Boa prática
  }

  instance_market_options {
    market_type = "spot"
    spot_options {
      spot_instance_type = "one-time"
    }
  }

  # User Data inline (bootstrap completo)
  user_data = templatefile("${path.module}/user_data.sh", {
    app_git_repo    = var.app_git_repo
    app_git_branch  = var.app_git_branch
    app_dir_name    = var.app_dir_name
    streamlit_entry = var.streamlit_entry
    ollama_model    = var.ollama_model
  })
}

resource "null_resource" "wait_for_userdata" {
  depends_on = [aws_instance.cpu_spot]

  triggers = {
    instance_id = aws_instance.cpu_spot.id
  }

  provisioner "local-exec" {
    command = <<EOT
      echo "Aguardando finalização do user_data na instância ${aws_instance.cpu_spot.id}..."
      
      # Loop de verificação (timeout de 15 minutos)
      sleep 30 
      for i in {1..90}; do
        STATUS=$(aws ssm send-command \
          --instance-ids "${aws_instance.cpu_spot.id}" \
          --document-name "AWS-RunShellScript" \
          --parameters 'commands=["if [ -f /var/lib/cloud/instance/sem/userdata.ok ]; then echo COMPLETED; else echo RUNNING; fi"]' \
          --query "Command.CommandId" \
          --output text \
          --region ${var.region})
        
        # Espera o comando SSM rodar e pega o output
        sleep 5
        RESULT=$(aws ssm list-command-invocations \
          --command-id "$STATUS" \
          --details \
          --query "CommandInvocations[0].CommandPlugins[0].Output" \
          --output text \
          --region ${var.region})

        if [[ "$RESULT" == *"COMPLETED"* ]]; then
          echo "✅ User_data finalizado com sucesso!"
          exit 0
        fi
        
        echo "⏳ Instalação em andamento... ($i/90)"
        sleep 10
      done

      echo "❌ Timeout: O user_data demorou mais de 15 minutos."
      exit 1
    EOT
    
    interpreter = ["/bin/bash", "-c"]
  }
}
