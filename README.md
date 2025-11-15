# 🚀 ToggleMaster - Arquitetura de Microsserviços

## ⚠️ ATENÇÃO IMPORTANTE - LEIA ANTES DE COMEÇAR ⚠️

### 🔴 O sistema NÃO funcionará completamente na primeira execução!

**Por quê?** O `evaluation-service` precisa de uma chave de API (`SERVICE_API_KEY`) para se comunicar com outros microsserviços. Esta chave:
- ❌ NÃO está pré-configurada no `docker-compose.yml`
- ✅ PRECISA ser criada após o `auth-service` estar rodando
- 📝 Simula um cenário real de Service-to-Service Authentication

### 🔑 Configuração Obrigatória do SERVICE_API_KEY

**Siga estes passos NA ORDEM:**

#### 1️⃣ Primeiro, suba todos os containers:
```bash
docker-compose up -d
```

#### 2️⃣ Aguarde 30 segundos para os serviços iniciarem, depois verifique:
```bash
docker-compose ps
# Todos devem estar "Up" ou "Up (healthy)"
```

#### 3️⃣ CRIE A CHAVE DE SERVIÇO (comando crucial):
```bash
curl -X POST http://localhost:8001/admin/keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer super-secret-master-key-2024" \
  -d '{"name": "evaluation-service-key"}'
```

**RESULTADO ESPERADO:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "evaluation-service-key", 
  "key": "tm_key_abc123xyz789",  # <-- COPIE ESTA CHAVE!
  "created_at": "2024-11-15T10:00:00Z"
}
```

#### 4️⃣ ADICIONE a chave ao `docker-compose.yml`:
```yaml
# Encontre a seção evaluation-service (linha ~222)
evaluation-service:
  environment:
    PORT: "8004"
    REDIS_URL: "redis://:redispass123@redis:6379/0"
    # ... outras variáveis ...
    SERVICE_API_KEY: "tm_key_abc123xyz789"  # <-- ADICIONE ESTA LINHA COM SUA CHAVE
```

#### 5️⃣ REINICIE o evaluation-service:
```bash
docker-compose restart evaluation-service
```

#### 6️⃣ TESTE se funcionou:
```bash
# Deve retornar true ou false, não um erro
curl "http://localhost:8004/evaluate?user_id=user-123&flag_name=test-flag"
```

#  🚀 Quick Start Guide - ToggleMaster

##  📋 Pré-requisitos

```bash
# Verificar Docker
docker --version
# Deve mostrar: Docker version 20.10.x ou superior

# Verificar Docker Compose
docker-compose --version
# Deve mostrar: docker-compose version 1.29.x ou superior

1. ✅ AWS CLI instalado
2. ✅ Credenciais AWS configuradas 
```

---

## 2️⃣ Criar Fila SQS no Norte da Virgínia

```bash
# Editar o .env
nano .env

# Coloque as informação de acessey key e secrety no arquivo.env

#Execute o script 
./setup-aws.sh

ou faça a criação da fila sqs de forma manual

# Criar a fila SQS
aws sqs create-queue \
    --queue-name togglemaster-events \
    --region us-east-1 \
    --attributes '{
        "VisibilityTimeout": "300",
        "MessageRetentionPeriod": "345600",
        "ReceiveMessageWaitTimeSeconds": "20"
    }'
```

**Saída esperada:**
```json
{
    "QueueUrl": "https://sqs.us-east-1.amazonaws.com/SEU_ACCOUNT_ID/togglemaster-events"
}
```

---

## 3️⃣ Copiar a URL da Fila

Copie a `QueueUrl` retornada e cole no arquivo `.env`:



---

## 4️⃣ Verificar a Fila

```bash
# Listar todas as filas
aws sqs list-queues --region us-east-1

# Ver atributos da fila
aws sqs get-queue-attributes \
    --queue-url https://sqs.us-east-1.amazonaws.com/SEU_ACCOUNT_ID/togglemaster-events \
    --attribute-names All \
    --region us-east-1
```

---

## 5️⃣ Testar Envio de Mensagem

```bash
# Enviar mensagem de teste
aws sqs send-message \
    --queue-url https://sqs.us-east-1.amazonaws.com/SEU_ACCOUNT_ID/togglemaster-events \
    --message-body '{"event": "test", "timestamp": "2025-11-14T15:00:00Z"}' \
    --region us-east-1

# Receber mensagens
aws sqs receive-message \
    --queue-url https://sqs.us-east-1.amazonaws.com/SEU_ACCOUNT_ID/togglemaster-events \
    --region us-east-1 \
    --max-number-of-messages 1
```

---

## 6️⃣ Subir o ToggleMaster

## 🚀 Como Usar Esta Entrega

### Passo 1: Extrair Arquivos

```bash
# Os arquivos estão em: togglemaster-microservices/
cd togglemaster-microservices
```

### Passo 2: Executar

```bash
# Opção A: Usar script helper
./togglemaster.sh start

# Opção B: Usar docker-compose diretamente
docker-compose up -d
```

### Passo 3: Verificar

```bash
# Verificar health
./togglemaster.sh health

# Ou manualmente
curl http://localhost:8001/health
curl http://localhost:8002/health
curl http://localhost:8003/health
curl http://localhost:8004/health
curl http://localhost:8005/health
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

---

## 📊 Monitoramento no Console AWS

1. Acesse: https://console.aws.amazon.com/sqs
2. Região: Norte da Virgínia (us-east-1)
3. Procure por: `togglemaster-events`
4. Veja:
   - Mensagens disponíveis
   - Mensagens em processamento
   - Mensagens na DLQ (se configurada)

---

## ⚠️ Observações Importantes

### Credenciais Temporárias

As credenciais fornecidas são **temporárias** (com session token)

- ✅ Válidas por: **4 horas**

---

## ✅ Checklist Final

Antes de subir o ToggleMaster:

- [ ] AWS CLI instalado
- [ ] Credenciais exportadas
- [ ] Fila SQS criada em us-east-1
- [ ] URL da fila copiada para `.env`
- [ ] Arquivo `.env` salvo
- [ ] `docker-compose build` executado
- [ ] `docker-compose up -d` executado

---



---

## 🆘 Problemas?

### Erro: "InvalidClientTokenId"
- Credenciais expiradas ou inválidas
- Solução: Gere novas credenciais temporárias

### Erro: "AccessDenied"
- Sem permissão para SQS
- Solução: Verifique IAM policies da sua conta

### Erro: "QueueDoesNotExist"
- URL da fila incorreta no `.env`
- Solução: Verifique a URL com `aws sqs list-queues`

---
