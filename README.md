# 🤖 Chatbot Streamlit + Ollama na AWS (Terraform)

Este projeto provisiona com Terraform uma instância EC2 (Spot) que roda um chatbot construído com Streamlit, LangChain e Ollama (ex.: `llama3.2`). A infraestrutura prioriza custo-benefício e facilita o acesso via AWS Systems Manager (SSM) para desenvolvimento e depuração.

## 🗺️ Arquitetura Simplificada

Usuário 🌐 → (porta 8501) → EC2 Spot (ex.: `g4dn.xlarge`)

- Streamlit (interface web)
- LangChain (orquestração)
- Ollama (LLM: `llama3.2`) — modelos baixados localmente na instância
- Histórico do chat (SQLite) — armazenado localmente (efêmero por padrão)

## ✨ Funcionalidades

- Implantação automatizada via Terraform.
- Custo-benefício com EC2 Spot e instâncias com GPU para LLMs.
- Stack pronto: Streamlit + LangChain + Ollama.
- Acesso e depuração via AWS SSM (Session Manager), sem necessidade de chaves SSH.
- Armazenamento local para modelos e histórico (considere EBS/S3 para persistência).

## 📋 Pré-requisitos

- Conta AWS com permissões para EC2, IAM, VPC e SSM.
- AWS CLI instalado e configurado.
- Terraform versão `>= 1.0.0`.
- Repositório Git contendo o código da aplicação Streamlit (referenciado por `app_git_repo`).

## 🏗️ Estrutura do Projeto

```
.
├── main.tf                 # Recursos AWS (EC2, IAM, Security Group)
├── variables.tf            # Variáveis de entrada
├── outputs.tf              # Saídas do Terraform
├── terraform.tfvars        # Valores do seu ambiente (não commitar)
├── user_data.sh            # Script de bootstrap da instância
└── README.md               # Este arquivo
```

## ⚙️ Configuração

1. Clone o repositório:

```bash
git clone <URL_DO_SEU_REPOSITORIO>
cd <NOME_DO_REPOSITORIO>
```

2. Edite `terraform.tfvars` (crie se não existir):

```hcl
# terraform.tfvars
region          = "us-east-1"
instance_type   = "t3.large"
key_name        = "seu-par-de-chaves-ec2" # Opcional
allowed_cidr    = "SEU_IP_PUBLICO/32"    # Ex: "203.0.113.45/32" para consultar https://meuip.com.br/
app_git_repo    = "https://github.com/seu-usuario/seu-repo-streamlit.git"
app_git_branch  = "main"
app_dir_name    = "chatbot-app"
streamlit_entry = "chat_stream.py"
ollama_model    = "llama3.2:3b"
```

⚠️ Atenção:
- Substitua `SEU_IP_PUBLICO/32` pelo seu IP público para restringir o acesso.
- `key_name` é opcional se você usar apenas SSM; crie um par de chaves na AWS se precisar de SSH.
- Garanta que `app_git_repo`, `app_git_branch`, `app_dir_name` e `streamlit_entry` correspondem ao seu repositório.

3. Verifique `user_data.sh` para confirmar nomes e caminhos usados no bootstrap.

## 🚀 Deploy

1. Inicialize o Terraform:

```bash
terraform init
```

2. Revise o plano:

```bash
terraform plan
```

3. Aplique as mudanças:

```bash
terraform apply
```

Confirme com `yes` quando solicitado. O provisionamento e o download do(s) modelo(s) podem levar alguns minutos (até ~15 min).

## 🌐 Acesso ao Chatbot

1. Obtenha a URL do Streamlit:

```bash
terraform output streamlit_url
```

O output deve ser algo como `http://<IP_PÚBLICO>:8501`.

2. Acesse o chatbot no navegador usando a URL retornada.

3. Depuração via SSM (se necessário):

```bash
terraform output ssm_command
# ou
aws ssm start-session --target <INSTANCE_ID>
```

Verifique logs dentro da instância:

```bash
sudo journalctl -u streamlit -f
sudo journalctl -u ollama -f
```

## 🔧 Troubleshooting

- Chatbot não carrega: verifique `allowed_cidr`, logs do Streamlit/Ollama e se a porta 8501 está aberta.
- Ollama não baixa o modelo: confirme conectividade da instância e nome correto do modelo.
- Erros no `user_data.sh`: verifique `/var/log/cloud-init-output.log` via SSM.

## 💰 Custos e limpeza

- Instâncias Spot reduzem custos, mas são interrompíveis; não são recomendadas sem estratégias de resiliência para produção.
- Para evitar custos, rode `terraform destroy` quando não usar os recursos:

```bash
terraform destroy
```

## 📝 Notas importantes

- **Dados efêmeros**: o armazenamento local da instância (instance store) é temporário; para persistência use EBS ou S3.
- **Segurança**: mantenha `allowed_cidr` restritivo (seu IP `/32`). Evite `0.0.0.0/0` em produção.
- **Produção**: considere Multi-AZ, ALB, Auto Scaling e armazenamento persistente para ambientes críticos.

---

