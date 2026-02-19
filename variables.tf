variable "region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.xlarge"
}

variable "key_name" {
  type    = string
  default = "ollama-keypair"
}

variable "allowed_cidr" {
  description = "Seu IP/32 para acessar Streamlit"
  type        = string
  default     = "0.0.0.0/0"  # Mude para seu IP/32
}

variable "app_git_repo" {
  description = "Repo Git do seu app"
  type        = string
  default     = "https://github.com/SEU_USUARIO/SEU_REPO.git"
}

variable "app_git_branch" {
  type    = string
  default = "main"
}

variable "app_dir_name" {
  type    = string
  default = "app"
}

variable "streamlit_entry" {
  type    = string
  default = "chat_stream.py"
}

variable "ollama_model" {
  type    = string
  default = "llama3.2"
}