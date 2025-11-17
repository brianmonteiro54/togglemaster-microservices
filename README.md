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

### Passo 3: Dar Permissão ao Script Principal

```bash
# Tornar o script togglemaster executável
chmod +x togglemaster.sh
```

---

## 🔐 Configuração da API Key

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
  "key": "tm_key_a53ad846291f1c86f0aac1b1e9af2c4b09eb86c3d5b7ed4c6cdd64c541fc7766",
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
SERVICE_API_KEY=tm_key_a53ad846291f1c86f0aac1b1e9af2c4b09eb86c3d5b7ed4c6cdd64c541fc7766
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

## 🧭 Arquitetura & Portas 
Consulte a [📘 Referência de API](./API_REFERENCE.md).


| Serviço             | Porta | Descrição                                                     | Endpoints principais (exemplos)                           |
|---------------------|:----:|---------------------------------------------------------------|-----------------------------------------------------------|
| **Auth Service**    | 8001 | Criação/validação de chaves de API                            | `POST /admin/keys`, `GET /validate`                       |
| **Flag Service**    | 8002 | CRUD de *feature flags*                                       | `GET /flags`, `POST /flags`, `PUT /flags/{name}`          |
| **Targeting Service**| 8003 | Regras de segmentação/rollout                                 |`POST /rules`,`GET /rules/{flag_name}`,`PUT /rules/{flag_name}`|
| **Evaluation Service**| 8004 | Decide exibir/ocultar *feature* por usuário                  | `GET /evaluate?user_id=...&flag_name=...`                 |
| **Analytics Service**| 8005 | *Worker* que consome SQS e grava no DynamoDB (somente health) | `GET /health`                                             |

---

# 🚀 Usando a Aplicação (Exemplos)

Depois que os containers estiverem rodando (após a **"Segunda Inicialização"**), você pode interagir com a API. Use a chave de API que gerou e configurou no `.env`.

> **Nota:** Nos exemplos abaixo, usamos a chave `tm_key_a53ad846...` apenas como ilustração. **Substitua pela sua chave gerada**.

---

## 1) Auth Service (Porta **8001**)

O **auth-service** é usado para criar e validar chaves. Você já o utilizou para criar a chave principal, mas também pode usá-lo para testar a validação.

### a) Validar sua chave de API
> Substitua `tm_key_...` pela sua chave.

```bash
curl http://localhost:8001/validate \
-H "Authorization: Bearer tm_key_a53ad846291f1c86f0aac1b1e9af2c4b09eb86c3d5b7ed4c6cdd64c541fc7766"
```
## 🧪 Usando a Aplicação (Exemplos)

### 1) Auth Service (8001)

O **auth-service** é usado para criar e validar chaves. Você já o utilizou para criar a chave principal, mas também pode usá-lo para testar a validação.

**Validar sua chave de API** (substitua a chave pelo seu valor real):
```bash
curl http://localhost:8001/validate \
  -H "Authorization: Bearer tm_key_a53ad846291f1c86f0aac1b1e9af2c4b09eb86c3d5b7ed4c6cdd64c541fc7766"
```

**Retorno esperado (se válida):**
```json
{
  "message": "Chave válida"
}
```

---

### 2) Flag Service (8002)

O **flag-service** gerencia as definições das suas feature flags.

**Criar uma nova Flag:**
```bash
curl -X POST http://localhost:8002/flags \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer tm_key_a53ad846291f1c86f0aac1b1e9af2c4b09eb86c3d5b7ed4c6cdd64c541fc7766" \
  -d '{
        "name": "enable-new-dashboard",
        "description": "Ativa o novo dashboard para usuários",
        "is_enabled": true
      }'
```

**Retorno esperado:**
```json
{
  "created_at": "Sun, 16 Nov 2025 20:57:30 GMT",
  "description": "Ativa o novo dashboard para usuários",
  "id": 1,
  "is_enabled": true,
  "name": "enable-new-dashboard",
  "updated_at": "Sun, 16 Nov 2025 20:57:30 GMT"
}
```

**Listar todas as Flags:**
```bash
curl http://localhost:8002/flags \
  -H "Authorization: Bearer tm_key_a53ad846291f1c86f0aac1b1e9af2c4b09eb86c3d5b7ed4c6cdd64c541fc7766"
```

**Desativar a Flag (PUT):**
```bash
curl -X PUT http://localhost:8002/flags/enable-new-dashboard \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer tm_key_a53ad846291f1c86f0aac1b1e9af2c4b09eb86c3d5b7ed4c6cdd64c541fc7766" \
  -d '{"is_enabled": false}'
```

---

### 3) Targeting Service (8003)

O **targeting-service** gerencia as regras de segmentação para cada flag.

**Criar uma Regra de Segmentação (50% rollout):**
```bash
curl -X POST http://localhost:8003/rules \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer tm_key_a53ad846291f1c86f0aac1b1e9af2c4b09eb86c3d5b7ed4c6cdd64c541fc7766" \
  -d '{
        "flag_name": "enable-new-dashboard",
        "is_enabled": true,
        "rules": {
          "type": "PERCENTAGE",
          "value": 50
        }
      }'
```

**Buscar a Regra criada:**
```bash
curl http://localhost:8003/rules/enable-new-dashboard \
  -H "Authorization: Bearer tm_key_a53ad846291f1c86f0aac1b1e9af2c4b09eb86c3d5b7ed4c6cdd64c541fc7766"
```

---

### 4) Evaluation Service (8004)

O **evaluation-service** é o endpoint principal que suas aplicações usam para decidir se exibem ou não uma *feature*.

**Teste com `user-123`:**
```bash
curl "http://localhost:8004/evaluate?user_id=user-123&flag_name=enable-new-dashboard"
```
**Retorno esperado (exemplo):**
```json
{
  "flag_name": "enable-new-dashboard",
  "user_id": "user-123",
  "result": true
}
```

**Teste com `user-abc`:**
```bash
curl "http://localhost:8004/evaluate?user_id=user-abc&flag_name=enable-new-dashboard"
```
**Retorno esperado (exemplo):**
```json
{
  "flag_name": "enable-new-dashboard",
  "user_id": "user-abc",
  "result": false
}
```

---

### 5) Analytics Service (8005)

Este serviço é um **worker**, não possui endpoints de API para uso (exceto o de **health**). Ele consome os eventos da fila **SQS** (gerados pelo `evaluation-service`) e salva-os no **DynamoDB**.

**Verificar Saúde:**
```bash
curl http://localhost:8005/health
```

**Verificar os Dados no DynamoDB:**

```bash
aws dynamodb scan \
    --table-name ToggleMasterAnalytics \
    --endpoint-url http://localhost:8000
```

