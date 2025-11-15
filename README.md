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
```bash
# Clone repository
git clone https://github.com/brianmonteiro54/togglemaster-microservices.git

cd togglemaster-microservices

# Configurar ambiente
cp .env.example .env
# Edite o arquivo .env com suas credenciais da AWS

# Configure os recursos da AWS (fila SQS)
chmod +x setup-aws.sh
./setup-aws.sh

```bash
# Usar script helper
./togglemaster.sh start

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

## ⚠️ Observações Importantes

### Credenciais Temporárias

As credenciais fornecidas são **temporárias** (com session token)

- ✅ Válidas por: **4 horas**

---