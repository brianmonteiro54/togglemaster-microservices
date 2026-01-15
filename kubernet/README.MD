# ToggleMaster - Kubernetes Deployment Guide

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![AWS EKS](https://img.shields.io/badge/AWS_EKS-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)
![External Secrets](https://img.shields.io/badge/External_Secrets-6C5CE7?style=for-the-badge)

## 📋 Índice

- [Visão Geral](#-visão-geral)
- [Pré-requisitos](#-pré-requisitos)
- [Guia de Implantação](#-guia-de-implantação)
  - [1. Configurar Acesso ao Cluster EKS](#1-configurar-acesso-ao-cluster-eks)
  - [2. Instalar o NGINX Ingress Controller](#2-instalar-o-nginx-ingress-controller)
  - [3. Instalar o External Secrets Operator](#3-instalar-o-external-secrets-operator)
  - [4. Deploy dos Namespaces](#4-deploy-dos-namespaces)
  - [5. Atualizar Credenciais AWS](#5-atualizar-credenciais-aws)
  - [6. Deploy dos Serviços](#6-deploy-dos-serviços)
  - [7. Deploy do HPA](#7-deploy-do-hpa)
  - [8. Verificação](#8-verificação)
- [Limitações do IRSA no VocLabs](#-limitações-do-irsa-no-voclabs)
- [Manutenção](#-manutenção)
- [Troubleshooting](#-troubleshooting)

---

## 🎯 Visão Geral

Este repositório contém os manifests Kubernetes para deploy da plataforma **ToggleMaster** - um sistema de Feature Flags distribuído composto por 5 microserviços:

| Serviço | Porta | Função |
|---------|-------|--------|
| **auth-service** | 8001 | Autenticação e gerenciamento de API Keys |
| **flag-service** | 8002 | CRUD de Feature Flags |
| **targeting-service** | 8003 | Regras de segmentação |
| **evaluation-service** | 8004 | Hot path - avaliação em tempo real |
| **analytics-service** | 8005 | Consumidor de eventos (SQS → DynamoDB) |

---

## 📦 Pré-requisitos

Antes de iniciar, certifique-se de ter:

- [ ] **AWS CLI** instalado e configurado
- [ ] **kubectl** instalado (v1.28+)
- [ ] **Helm** instalado (v3.x)
- [ ] Acesso ao **AWS Academy Learner Lab** (ou conta AWS com EKS)
- [ ] Cluster **EKS** já provisionado
- [ ] Recursos AWS criados:
  - RDS PostgreSQL (auth, flag, targeting)
  - ElastiCache Redis
  - SQS Queue
  - DynamoDB Table
  - Secrets no AWS Secrets Manager

---

---

## 🚀 Guia de Implantação

### 1. Configurar Acesso ao Cluster EKS

#### 1.1 Obter credenciais do AWS Learner Lab

Acesse o **AWS Academy Learner Lab** e clique em **AWS Details** para obter:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`

#### 1.2 Configurar AWS CLI

```bash
# Opção 1: Exportar variáveis de ambiente
export AWS_ACCESS_KEY_ID="sua_access_key"
export AWS_SECRET_ACCESS_KEY="sua_secret_key"
export AWS_SESSION_TOKEN="seu_session_token"
export AWS_DEFAULT_REGION="us-east-1"

# Opção 2: Configurar via arquivo
aws configure
# Depois adicione o session token em ~/.aws/credentials
```

#### 1.3 Obter kubeconfig do EKS

```bash
# Substitua 'nome-do-cluster' pelo nome do seu cluster EKS
aws eks update-kubeconfig --name nome-do-cluster --region us-east-1

# Verificar conexão com o cluster
kubectl cluster-info

# Verificar nodes
kubectl get nodes
```

**Saída esperada:**
```
NAME                             STATUS   ROLES    AGE   VERSION
ip-10-0-1-xxx.ec2.internal       Ready    <none>   1d    v1.28.x
ip-10-0-2-xxx.ec2.internal       Ready    <none>   1d    v1.28.x
```

---

### 2. Instalar o NGINX Ingress Controller

O Ingress Controller é necessário para expor o `evaluation-service` externamente.

```bash
# Adicionar repositório Helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Instalar NGINX Ingress Controller
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer

# Aguardar o LoadBalancer ser provisionado (pode levar 2-3 minutos)
kubectl get svc -n ingress-nginx -w

# Obter o endereço do LoadBalancer
kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

---

### 3. Instalar o External Secrets Operator

O ESO permite sincronizar secrets do AWS Secrets Manager com o Kubernetes.

```bash
# Instalar CRDs
kubectl apply -f https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/crds/bundle.yaml --server-side=true

# Adicionar repositório Helm
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Instalar External Secrets Operator
helm install external-secrets external-secrets/external-secrets \
  --namespace kube-system \
  --set installCRDs=false \
  --set webhook.port=9443

# Verificar instalação
kubectl get pods -n kube-system | grep external-secrets
```

**Saída esperada:**
```
external-secrets-xxxxxxxxx-xxxxx           1/1     Running   0          1m
external-secrets-cert-controller-xxxxxx    1/1     Running   0          1m
external-secrets-webhook-xxxxxxxxx-xxxxx   1/1     Running   0          1m
```

---

### 4. Deploy dos Namespaces

```bash
# Aplicar namespaces
kubectl apply -f namespace.yaml

# Verificar criação
kubectl get namespaces | grep togglemaster
```

**Saída esperada:**
```
togglemaster-analytics    Active   10s
togglemaster-auth         Active   10s
togglemaster-evaluation   Active   10s
togglemaster-flag         Active   10s
togglemaster-targeting    Active   10s
```

---

### 5. Atualizar Credenciais AWS

⚠️ **IMPORTANTE**: Antes de aplicar os manifests, atualize as credenciais AWS em todos os arquivos de secrets.

#### 5.1 Gerar credenciais em Base64

```bash
# No terminal, encode suas credenciais
echo -n "SUA_AWS_ACCESS_KEY_ID" | base64
echo -n "SUA_AWS_SECRET_ACCESS_KEY" | base64
echo -n "SEU_AWS_SESSION_TOKEN" | base64
```

#### 5.2 Atualizar os arquivos

Edite os seguintes arquivos substituindo os valores em `data:`:

| Arquivo | Chaves a atualizar |
|---------|-------------------|
| `togglemaster-auth/external-secrets.yaml` | `access-key`, `secret-access-key`, `session-token` |
| `togglemaster-flag/external-secrets.yaml` | `access-key`, `secret-access-key`, `session-token` |
| `togglemaster-targeting/external-secrets.yaml` | `access-key`, `secret-access-key`, `session-token` |
| `togglemaster-evaluation/aws-credentials.yaml` | `access-key`, `secret-access-key`, `session-token` |
| `togglemaster-analytics/aws-credentials.yaml` | `access-key`, `secret-access-key`, `session-token` |

**Exemplo de edição:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: aws-credentials
  namespace: togglemaster-auth
type: Opaque
data:
  access-key: <SEU_ACCESS_KEY_BASE64>
  secret-access-key: <SEU_SECRET_ACCESS_KEY_BASE64>
  session-token: <SEU_SESSION_TOKEN_BASE64>
```

---

### 6. Deploy dos Serviços

Execute os deploys na ordem correta (respeitando dependências):

```bash
# 1. Auth Service (sem dependências internas)
echo ">>> Deploying Auth Service..."
kubectl apply -f togglemaster-auth/external-secrets.yaml
kubectl apply -f togglemaster-auth/auth-service.yaml

# Aguardar pods ficarem Ready
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=auth-service \
  -n togglemaster-auth --timeout=120s

# 2. Flag Service (depende do Auth)
echo ">>> Deploying Flag Service..."
kubectl apply -f togglemaster-flag/external-secrets.yaml
kubectl apply -f togglemaster-flag/flag-service.yaml

kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=flag-service \
  -n togglemaster-flag --timeout=120s

# 3. Targeting Service (depende do Auth e Flag)
echo ">>> Deploying Targeting Service..."
kubectl apply -f togglemaster-targeting/external-secrets.yaml
kubectl apply -f togglemaster-targeting/targeting-service.yaml

kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=targeting-service \
  -n togglemaster-targeting --timeout=120s

# 4. Evaluation Service (depende do Flag e Targeting)
echo ">>> Deploying Evaluation Service..."
kubectl apply -f togglemaster-evaluation/aws-credentials.yaml
kubectl apply -f togglemaster-evaluation/evaluation-service.yaml

kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=evaluation-service \
  -n togglemaster-evaluation --timeout=120s

# 5. Analytics Service (independente)
echo ">>> Deploying Analytics Service..."
kubectl apply -f togglemaster-analytics/aws-credentials.yaml
kubectl apply -f togglemaster-analytics/analytics-service.yaml

kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=analytics-service \
  -n togglemaster-analytics --timeout=120s

echo ">>> Deploy completo!"
```

---

### 7. Deploy do HPA

```bash
# Aplicar HorizontalPodAutoscaler
kubectl apply -f hpa.yaml

# Verificar HPA
kubectl get hpa -n togglemaster-evaluation
```

---

### 8. Verificação

#### 8.1 Verificar todos os pods

```bash
kubectl get pods -A -l app.kubernetes.io/part-of=togglemaster
```

**Saída esperada:**
```
NAMESPACE                 NAME                                  READY   STATUS    RESTARTS   AGE
togglemaster-analytics    analytics-service-xxxxxxxxx-xxxxx     1/1     Running   0          2m
togglemaster-auth         auth-service-xxxxxxxxx-xxxxx          1/1     Running   0          5m
togglemaster-auth         auth-service-xxxxxxxxx-yyyyy          1/1     Running   0          5m
togglemaster-evaluation   evaluation-service-xxxxxxxxx-xxxxx    1/1     Running   0          3m
togglemaster-evaluation   evaluation-service-xxxxxxxxx-yyyyy    1/1     Running   0          3m
togglemaster-flag         flag-service-xxxxxxxxx-xxxxx          1/1     Running   0          4m
togglemaster-flag         flag-service-xxxxxxxxx-yyyyy          1/1     Running   0          4m
togglemaster-targeting    targeting-service-xxxxxxxxx-xxxxx     1/1     Running   0          3m
togglemaster-targeting    targeting-service-xxxxxxxxx-yyyyy     1/1     Running   0          3m
```

#### 8.2 Verificar External Secrets

```bash
# Verificar se os secrets foram sincronizados
kubectl get externalsecrets -A

# Verificar status detalhado
kubectl get externalsecrets -n togglemaster-auth auth-service-rds -o yaml
```

**Status esperado:** `SecretSynced`

#### 8.3 Verificar Ingress

```bash
# Obter IP/DNS do LoadBalancer
kubectl get ingress -n togglemaster-evaluation

# Testar endpoint de health
INGRESS_HOST=$(kubectl get ingress -n togglemaster-evaluation evaluation-service-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl -I http://$INGRESS_HOST/health
```

#### 8.4 Verificar HPA

```bash
kubectl get hpa -n togglemaster-evaluation

# Output esperado:
# NAME                      REFERENCE                       TARGETS   MINPODS   MAXPODS   REPLICAS
# evaluation-service-hpa    Deployment/evaluation-service   10%/30%   2         20        2
```

---

## ⚠️ Limitações do IRSA no VocLabs

### Por que usamos credenciais estáticas?

Para gerenciar as credenciais dos bancos RDS de forma segura, a arquitetura utiliza o **External Secrets Operator (ESO)** integrado ao **AWS Secrets Manager**. A abordagem recomendada pela AWS seria o **IRSA (IAM Roles for Service Accounts)**, que permite que pods assumam IAM Roles usando tokens OIDC — eliminando credenciais estáticas.

### O Problema

Durante a configuração no ambiente **AWS Academy Learner Lab**, encontramos uma cadeia de bloqueios:

| Tentativa | Resultado | Motivo |
|-----------|-----------|--------|
| Usar IRSA nativamente | ❌ Falhou | OIDC Provider inexistente no cluster |
| Criar OIDC Provider via `eksctl` | ❌ Bloqueado | `AccessDenied` em `iam:CreateOpenIDConnectProvider` |
| Modificar Trust Policy do LabRole | ❌ Bloqueado | `Deny` explícito em `iam:Update*` no LabRole |

**Sintomas observados:**
- SecretStore com status `InvalidProviderConfig`
- ExternalSecrets retornando `SecretSyncedError`
- Nenhum Secret sendo criado no Kubernetes

### A Solução Adotada

Implementamos autenticação via **credenciais temporárias do Learner Lab**:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: aws-credentials
type: Opaque
data:
  access-key: <BASE64_ACCESS_KEY>
  secret-access-key: <BASE64_SECRET_ACCESS_KEY>
  session-token: <BASE64_SESSION_TOKEN>
```

O SecretStore foi configurado para usar `secretRef` em vez de `jwt`:

```yaml
apiVersion: external-secrets.io/v1
kind: SecretStore
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        secretRef:  # Em vez de jwt/IRSA
          accessKeyIDSecretRef:
            name: aws-credentials
            key: access-key
          # ... demais refs
```
---

## 🔧 Manutenção

### Atualizar Credenciais AWS (quando expirarem)

As credenciais do Learner Lab expiram a cada **~4 horas**. Para atualizar:

```bash
# 1. Obter novas credenciais no Learner Lab (AWS Details)

# 2. Gerar Base64
ACCESS_KEY_B64=$(echo -n "NOVA_ACCESS_KEY" | base64)
SECRET_KEY_B64=$(echo -n "NOVA_SECRET_KEY" | base64)
SESSION_TOKEN_B64=$(echo -n "NOVO_SESSION_TOKEN" | base64)

# 3. Atualizar secrets em cada namespace
for ns in togglemaster-auth togglemaster-flag togglemaster-targeting togglemaster-evaluation togglemaster-analytics; do
  kubectl patch secret aws-credentials -n $ns \
    -p "{\"data\":{\"access-key\":\"$ACCESS_KEY_B64\",\"secret-access-key\":\"$SECRET_KEY_B64\",\"session-token\":\"$SESSION_TOKEN_B64\"}}"
done

# 4. Forçar re-sync dos ExternalSecrets
for ns in togglemaster-auth togglemaster-flag togglemaster-targeting; do
  kubectl annotate externalsecret -n $ns --all force-sync=$(date +%s) --overwrite
done

# 5. Reiniciar pods para pegar novas credenciais
kubectl rollout restart deployment -n togglemaster-evaluation evaluation-service
kubectl rollout restart deployment -n togglemaster-analytics analytics-service
```

### Verificar Logs

```bash
# Auth Service
kubectl logs -n togglemaster-auth -l app.kubernetes.io/name=auth-service -f

# Evaluation Service (hot path)
kubectl logs -n togglemaster-evaluation -l app.kubernetes.io/name=evaluation-service -f

# External Secrets Operator
kubectl logs -n kube-system -l app.kubernetes.io/name=external-secrets -f
```

---

## 🔍 Troubleshooting

### Pod em CrashLoopBackOff

```bash
# Verificar logs do pod
kubectl logs -n <namespace> <pod-name> --previous

# Verificar eventos
kubectl describe pod -n <namespace> <pod-name>
```

### ExternalSecret não sincroniza

```bash
# Verificar status do SecretStore
kubectl get secretstore -n <namespace> -o yaml

# Verificar status do ExternalSecret
kubectl get externalsecret -n <namespace> -o yaml

# Causas comuns:
# - Credenciais AWS expiradas → Atualizar aws-credentials
# - ARN do secret incorreto → Verificar key no remoteRef
# - Região incorreta → Verificar region no SecretStore
```

### Ingress sem IP/DNS

```bash
# Verificar se o Ingress Controller está rodando
kubectl get pods -n ingress-nginx

# Verificar eventos do service
kubectl describe svc -n ingress-nginx ingress-nginx-controller

# Verificar se o Security Group permite tráfego nas portas 80/443
```

### Pods não conseguem se comunicar

```bash
# Testar DNS interno
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup auth-service.togglemaster-auth.svc.cluster.local

# Testar conectividade
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://auth-service.togglemaster-auth.svc.cluster.local:8001/health
```

---