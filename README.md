## 💼 Sobre este projeto

**ToggleMaster** é um sistema de **Feature Flags** distribuído e pronto para produção, construído com arquitetura moderna de microsserviços. Este projeto demonstra a implementação completa de provisionamento, conteinerização, orquestração e escalabilidade de infraestrutura em nuvem na AWS.

> 🎓 **Contexto Acadêmico:** Desenvolvido como parte do Programa de Pós-Graduação em DevOps e Arquitetura em Nuvem da FIAP (Desafio Tecnológico Fase 2)

🔗 Base: [togglemaster-microservices-main](https://github.com/orgs/FIAP-TCs/repositories)


##  📋 Pré-requisitos

```bash
# Verificar Docker
docker --version
# Deve mostrar: Docker version 29.x.x ou superior

# Verificar Docker Compose
docker-compose --version
# Deve mostrar: docker-compose version 1.29.x ou superior

1. ✅ AWS CLI instalado
2. ✅ Credenciais AWS configuradas 
```
## 🚀 Guia de Instalação

### Passo 1: Clonar o Repositório

```bash
# Clone o repositório
git clone https://github.com/brianmonteiro54/togglemaster-microservices.git

# Acesse o diretório do projeto
cd togglemaster-microservices
```

### Passo 2: Configurar Variáveis de Ambiente

```bash
# Copiar o arquivo de exemplo
cp .env.example .env
```

**Edite o arquivo `.env` com suas credenciais da AWS:**

```dotenv
# =============================================================================
# AWS CREDENTIALS
# =============================================================================
AWS_ACCESS_KEY_ID=sua_access_key_aqui
AWS_SECRET_ACCESS_KEY=sua_secret_key_aqui
AWS_SESSION_TOKEN=seu_session_token_aqui

# URL da fila SQS (será preenchida após executar setup-aws.sh)
SQS_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/SEU_ACCOUNT_ID/togglemaster-events

# =============================================================================
# SERVICE CREDENTIALS
# ============================================================================
SERVICE_API_KEY=tm_key_xxxx # ATENÇÃO: Será configurado após a primeira inicialização
MASTER_KEY=super-secret-master-key-2026
```

### Passo 3: Configurar Recursos AWS

```bash
# Tornar o script executável
chmod +x setup-aws.sh

# Executar configuração da AWS (cria a fila SQS)
./setup-aws.sh
```
### Passo 4: Dar Permissão ao Script Principal

```bash
# Tornar o script togglemaster executável
chmod +x togglemaster.sh
```

---

## 🔐 Configuração da API Key e DynamoDB

### ⚠️ Atenção: Processo de Duas Etapas

A configuração da `SERVICE_API_KEY` requer **duas inicializações** do sistema. Siga os passos abaixo cuidadosamente:

### Primeira Inicialização

1. **Inicie os serviços pela primeira vez:**

```bash
./togglemaster.sh start
```

2. **Aguarde os serviços subirem** (aproximadamente 10-15 segundos)

3. **Gere uma  API key:**

```bash
curl -X POST http://localhost:8001/admin/keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer super-secret-master-key-2026" \
  -d '{"name": "evaluation-service-key"}'
```

4. **Você receberá uma resposta como esta:**

```json
{
  "name": "evaluation-service-key",
  "key": "tm_key_6e2134acbde1dc8761629e10475b7242d18e647707424924b4572a7035c5386b",
  "message": "Guarde esta chave com segurança! Você não poderá vê-la novamente."
}
```

5. **⚠️ IMPORTANTE:** Copie o valor da chave (`tm_key_...`) imediatamente!

### Configurar a API Key no .env

1. **Abra o arquivo `.env` e atualize a linha:**

```dotenv
# Antes (vazio):
SERVICE_API_KEY=

# Depois (com a chave gerada):
SERVICE_API_KEY=tm_key_6e2134acbde1dc8761629e10475b7242d18e647707424924b4572a7035c5386b
```

**Crie a tabela do DynamoDB Local**: O **analytics-service** precisa desta tabela para gravar os eventos. Use o comando abaixo para criá-la no dynamodb-local

```bash
aws dynamodb create-table \
    --table-name ToggleMasterAnalytics \
    --attribute-definitions \
        AttributeName=event_id,AttributeType=S \
    --key-schema \
        AttributeName=event_id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --endpoint-url http://localhost:8000
```

### Segunda Inicialização (Final)

1. **Pare os serviços:**

```bash
./togglemaster.sh stop
```

2. **Inicie novamente com a chave configurada:**

```bash
./togglemaster.sh start
```


---

## 🔧 Comandos Úteis

```bash
./togglemaster.sh help     # Lista todos os comandos
./togglemaster.sh health   # Verifica saúde dos serviços
./togglemaster.sh logs     # Visualiza logs
```

### Ver Métricas da Fila
```bash
aws sqs get-queue-attributes \
    --queue-url https://sqs.us-east-1.amazonaws.com/SEU_ACCOUNT_ID/togglemaster-events \
    --attribute-names ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible \
    --region us-east-1
```

### Purgar Fila (Limpar Todas as Mensagens)
```bash
aws sqs purge-queue \
    --queue-url https://sqs.us-east-1.amazonaws.com/SEU_ACCOUNT_ID/togglemaster-events \
    --region us-east-1
```

### Deletar Fila
```bash
aws sqs delete-queue \
    --queue-url https://sqs.us-east-1.amazonaws.com/SEU_ACCOUNT_ID/togglemaster-events \
    --region us-east-1
```