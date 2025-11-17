# 📘 Referência de API

Tabela de rotas e métodos principais dos serviços.

## Auth Service (8001)
Responsável pela **gestão e validação de chaves de API**, incluindo a criação de SERVICE_API_KEYs para outros serviços e a verificação de chaves em uso nas chamadas autenticadas.

| Método | Rota          | Corpo (exemplo)                                                                                          | Descrição                 | Autenticação |
|:-----:|----------------|-----------------------------------------------------------------------------------------------------------|---------------------------|:------------:|
| POST   | `/admin/keys` | `{"name": "evaluation-service-key"}`                                                                                                      | Cria uma nova chave do SERVICE_API_KEY       | Bearer {MASTER_KEY} |
| GET  | `/validate`       |  | Valida a chave de API        | Bearer {SERVICE_API_KEY} |

## Flag Service (8002)
Responsável por **criar, listar e gerenciar feature flags**, definindo quais funcionalidades podem ser ligadas ou desligadas globalmente no sistema.

| Método | Rota          | Corpo (exemplo)                                                                                          | Descrição                 | Autenticação |
|:-----:|----------------|-----------------------------------------------------------------------------------------------------------|---------------------------|:------------:|
| POST  | `/flags`       | `{ "name": "enable-new-dashboard", "description": "Ativa o novo dashboard para usuários", "is_enabled": true }` | Cria uma nova flag        | Bearer {SERVICE_API_KEY} |
| GET   | `/flags`       | —                                                                                                         | Lista todas as flags      | Bearer {SERVICE_API_KEY} |
| PUT   | `/flags/{name}`| `{ "is_enabled": false } ou { "is_enabled": true }`                                                                                | Ativa/Desativa a flag  | Bearer {SERVICE_API_KEY} |

## Targeting Service (8003)
Responsável por **definir e gerenciar regras de segmentação**, como rollout por porcentagem ou outras estratégias de targeting, para determinar quais usuários recebem determinada feature.

| Método | Rota     | Corpo (exemplo)                                                                                                               | Descrição                     | Autenticação |
|:-----:|----------|--------------------------------------------------------------------------------------------------------------------------------|-------------------------------|:------------:|
| POST  | `/rules` | `{ "flag_name": "enable-new-dashboard", "is_enabled": true, "rules": { "type": "PERCENTAGE", "value": 50 } }`                  | Cria/atualiza regra           | Bearer {SERVICE_API_KEY} |
| GET   | `/rules/{flag_name}` | —                                                                                                                  | Busca regra da flag           | Bearer  {SERVICE_API_KEY} |
| PUT   | `/rules/{flag_name}` | ` {"rules":{"type":"PERCENTAGE","value":75}}`                                                                                                               | Atualiza a regra de segmentação          | Bearer  {SERVICE_API_KEY} |

## Evaluation Service (8004)
Responsável por **avaliar, em tempo de execução, se um usuário específico deve ver ou não uma feature**, combinando o estado da flag e as regras de segmentação configuradas.

| Método | Rota                           | Descrição                                           | Autenticação |
|:-----:|---------------------------------|-----------------------------------------------------|:------------:|
| GET   | `/evaluate?user_id={id}&flag_name={flag}` | Avalia se um usuário deve ver a *feature* | --- |

## Analytics Service (8005)
Responsável por **consumir eventos de avaliação (via SQS) e registrar dados analíticos no DynamoDB**, permitindo auditoria, métricas de uso e análises sobre as ativações de feature flags.

| Método | Rota      | Descrição                                                                               | Autenticação |
|:-----:|------------|-----------------------------------------------------------------------------------------|:------------:|
| GET   | `/health`  | Verifica saúde do *worker* que consome SQS e grava no DynamoDB                          | — |
