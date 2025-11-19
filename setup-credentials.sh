#!/bin/bash

# =============================================================================
# ToggleMaster - Script de Configuração de Credenciais
# =============================================================================
# Este script configura automaticamente as credenciais seguras para o ambiente
# Suporta tanto execução local quanto na AWS real (incluindo AWS Academy)
# =============================================================================

set -e  # Para o script em caso de erro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Variáveis globais
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/setup.log"

# =============================================================================
# FUNÇÕES DE UTILIDADE
# =============================================================================

# Função para logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Função para mensagens de erro
error() {
    echo -e "${RED}❌ $*${NC}" >&2
    log "ERROR: $*"
}

# Função para mensagens de sucesso
success() {
    echo -e "${GREEN}✅ $*${NC}"
    log "SUCCESS: $*"
}

# Função para mensagens de aviso
warning() {
    echo -e "${YELLOW}⚠️  $*${NC}"
    log "WARN: $*"
}

# Função para mensagens informativas
info() {
    echo -e "${BLUE}ℹ️  $*${NC}"
    log "INFO: $*"
}

# Função para gerar senhas seguras
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Função para gerar tokens seguros
generate_token() {
    openssl rand -hex 32
}

# Função para limpar ambiente Docker
cleanup_docker_environment() {
    echo ""
    info "Limpando ambiente Docker..."
    
    # Parar containers
    if docker-compose ps -q 2>/dev/null | grep -q .; then
        info "Parando containers..."
        docker-compose down 2>/dev/null || true
        success "Containers parados"
    fi
    
    # Remover volumes
    local volumes=(
        "togglemaster-dynamodb-data"
        "togglemaster-localstack-data"
        "togglemaster-postgres-auth-data"
        "togglemaster-postgres-flag-data"
        "togglemaster-postgres-targeting-data"
        "togglemaster-redis-data"
    )
    
    info "Removendo volumes..."
    for volume in "${volumes[@]}"; do
        if docker volume inspect "$volume" >/dev/null 2>&1; then
            docker volume rm "$volume" 2>/dev/null && \
                echo "  ✓ $volume removido" || \
                echo "  ⚠ Falha ao remover $volume"
        fi
    done
    
    success "Ambiente limpo"
}

# =============================================================================
# FUNÇÕES AWS
# =============================================================================

# Função para validar e testar credenciais AWS
test_aws_credentials() {
    local test_output
    
    info "Testando credenciais AWS..." >&2
    
    # Tentar obter caller identity
    if ! test_output=$(aws sts get-caller-identity --output json 2>&1); then
        error "Falha ao validar credenciais AWS" >&2
        echo "$test_output" >&2
        return 1
    fi
    
    # Extrair informações
    local account_id=$(echo "$test_output" | grep -o '"Account"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    local user_arn=$(echo "$test_output" | grep -o '"Arn"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    
    success "Credenciais AWS válidas" >&2
    info "Account ID: ${account_id:-unknown}" >&2
    info "User/Role ARN: ${user_arn:-unknown}" >&2
    
    return 0
}

# Função para criar tabela DynamoDB
create_dynamodb_table() {
    local table_name="$1"
    local region="$2"
    
    info "Verificando tabela DynamoDB: ${table_name}..." >&2
    
    # Verificar se tabela já existe
    if aws dynamodb describe-table \
        --table-name "$table_name" \
        --region "$region" \
        --output json > /dev/null 2>&1; then
        
        success "Tabela DynamoDB '${table_name}' já existe" >&2
        return 0
    fi
    
    info "Criando tabela DynamoDB: ${table_name}..." >&2
    
    # Criar tabela
    local create_result
    if ! create_result=$(aws dynamodb create-table \
        --table-name "$table_name" \
        --attribute-definitions AttributeName=event_id,AttributeType=S \
        --key-schema AttributeName=event_id,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$region" \
        --tags Key=Project,Value=ToggleMaster Key=ManagedBy,Value=SetupScript \
        --output json 2>&1); then
        
        error "Falha ao criar tabela DynamoDB" >&2
        echo "$create_result" >&2
        return 1
    fi
    
    success "Tabela DynamoDB '${table_name}' criada" >&2
    
    # Aguardar tabela ficar ativa
    info "Aguardando tabela ficar ativa..." >&2
    
    local max_attempts=60  # 5 minutos (60 * 5 segundos)
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local status
        status=$(aws dynamodb describe-table \
            --table-name "$table_name" \
            --region "$region" \
            --query 'Table.TableStatus' \
            --output text 2>/dev/null || echo "UNKNOWN")
        
        if [ "$status" = "ACTIVE" ]; then
            echo "" >&2
            success "Tabela DynamoDB está ativa" >&2
            return 0
        fi
        
        echo -n "." >&2
        sleep 5
        attempt=$((attempt + 1))
    done
    
    echo "" >&2
    error "Timeout aguardando tabela ficar ativa" >&2
    return 1
}

# Função para criar fila SQS
create_sqs_queue() {
    local queue_name="$1"
    local region="$2"
    
    info "Verificando fila SQS: ${queue_name}..." >&2
    
    # Tentar obter URL da fila existente
    local queue_url
    queue_url=$(aws sqs get-queue-url \
        --queue-name "$queue_name" \
        --region "$region" \
        --output text \
        --query 'QueueUrl' 2>/dev/null || echo "")
    
    if [ -n "$queue_url" ]; then
        success "Fila SQS '${queue_name}' já existe" >&2
        info "URL da fila: ${queue_url}" >&2
        echo "$queue_url"
        return 0
    fi
    
    info "Criando fila SQS: ${queue_name}..." >&2
    
    # Criar fila e capturar apenas a URL
    local create_result
    create_result=$(aws sqs create-queue \
        --queue-name "$queue_name" \
        --attributes "VisibilityTimeout=300,MessageRetentionPeriod=345600,ReceiveMessageWaitTimeSeconds=20" \
        --tags "Project=ToggleMaster,ManagedBy=SetupScript" \
        --region "$region" \
        --output text \
        --query 'QueueUrl' 2>&1)
    
    if [ $? -ne 0 ]; then
        error "Falha ao criar fila SQS" >&2
        echo "$create_result" >&2
        return 1
    fi
    
    # A URL já vem limpa com --output text --query 'QueueUrl'
    queue_url="$create_result"
    
    if [ -z "$queue_url" ] || [[ ! "$queue_url" =~ ^https:// ]]; then
        error "URL da fila inválida: '$queue_url'" >&2
        return 1
    fi
    
    success "Fila SQS '${queue_name}' criada" >&2
    info "URL da fila: ${queue_url}" >&2
    
    # Retornar apenas a URL
    echo "$queue_url"
    return 0
}

# Função principal para criar recursos AWS
create_aws_resources() {
    local region="$1"
    
    echo "" >&2
    info "Criando recursos na AWS (região: ${region})..." >&2
    echo "" >&2
    
    # Testar credenciais
    if ! test_aws_credentials; then
        return 1
    fi
    
    echo "" >&2
    
    # Criar tabela DynamoDB
    if ! create_dynamodb_table "ToggleMasterAnalytics" "$region"; then
        return 1
    fi
    
    echo "" >&2
    
    # Criar fila SQS e capturar URL
    local queue_url
    queue_url=$(create_sqs_queue "togglemaster-events" "$region")
    local sqs_exit_code=$?
    
    if [ $sqs_exit_code -ne 0 ] || [ -z "$queue_url" ]; then
        error "Falha ao obter URL da fila SQS" >&2
        return 1
    fi
    
    echo "" >&2
    success "Todos os recursos AWS foram criados/verificados" >&2
    
    # Retornar APENAS a URL (sem cores, sem nada) na stdout
    echo "$queue_url"
}

# =============================================================================
# FUNÇÕES DE CONFIGURAÇÃO
# =============================================================================

# Função para criar arquivo .env
create_env_file() {
    local mode="$1"
    local aws_access_key="$2"
    local aws_secret_key="$3"
    local aws_session_token="$4"
    local aws_region="$5"
    local sqs_queue_url="$6"
    
    info "Gerando credenciais para serviços..."
    
    # Gerar credenciais únicas
    local postgres_auth_user="authuser_$(openssl rand -hex 4)"
    local postgres_auth_password=$(generate_password)
    
    local postgres_flag_user="flaguser_$(openssl rand -hex 4)"
    local postgres_flag_password=$(generate_password)
    
    local postgres_targeting_user="targetuser_$(openssl rand -hex 4)"
    local postgres_targeting_password=$(generate_password)
    
    local redis_password=$(generate_password)
    local master_key=$(generate_token)
    
    # Criar arquivo .env
    cat > .env << EOF
# =============================================================================
# ToggleMaster - Variáveis de Ambiente
# =============================================================================
# Gerado automaticamente em: $(date)
# Modo de execução: $([ "$mode" = "aws" ] && echo "AWS Real" || echo "Local (Docker)")
# =============================================================================

# =============================================================================
# POSTGRESQL - AUTH SERVICE
# =============================================================================
POSTGRES_AUTH_DB=authdb
POSTGRES_AUTH_USER=${postgres_auth_user}
POSTGRES_AUTH_PASSWORD=${postgres_auth_password}

# =============================================================================
# POSTGRESQL - FLAG SERVICE
# =============================================================================
POSTGRES_FLAG_DB=flagdb
POSTGRES_FLAG_USER=${postgres_flag_user}
POSTGRES_FLAG_PASSWORD=${postgres_flag_password}

# =============================================================================
# POSTGRESQL - TARGETING SERVICE
# =============================================================================
POSTGRES_TARGETING_DB=targetingdb
POSTGRES_TARGETING_USER=${postgres_targeting_user}
POSTGRES_TARGETING_PASSWORD=${postgres_targeting_password}

# =============================================================================
# REDIS
# =============================================================================
REDIS_PASSWORD=${redis_password}

# =============================================================================
# AWS CREDENTIALS
# =============================================================================
AWS_ACCESS_KEY_ID=${aws_access_key}
AWS_SECRET_ACCESS_KEY=${aws_secret_key}
EOF

    # Adicionar session token se existir
    if [ -n "$aws_session_token" ]; then
        echo "AWS_SESSION_TOKEN=${aws_session_token}" >> .env
    else
        echo "# AWS_SESSION_TOKEN=  # Não necessário para este ambiente" >> .env
    fi

    cat >> .env << EOF
AWS_REGION=${aws_region}

# =============================================================================
# SERVICE ENDPOINTS
# =============================================================================
SQS_QUEUE_URL=${sqs_queue_url}
EOF

    # Configurar endpoints baseado no modo
    if [ "$mode" = "aws" ]; then
        cat >> .env << EOF
# DYNAMODB_ENDPOINT_URL=http://dynamodb-local:8000  # Comentado - usando AWS Real
# AWS_ENDPOINT_URL=http://localstack:4566  # Comentado - usando AWS Real
EOF
    else
        cat >> .env << EOF
DYNAMODB_ENDPOINT_URL=http://dynamodb-local:8000
AWS_ENDPOINT_URL=http://localstack:4566
EOF
    fi

    cat >> .env << EOF

# =============================================================================
# SERVICE CREDENTIALS
# =============================================================================
SERVICE_API_KEY=
MASTER_KEY=${master_key}

# =============================================================================
# SERVICE URLS (Internal Communication)
# =============================================================================
AUTH_SERVICE_URL=http://auth-service:8001
FLAG_SERVICE_URL=http://flag-service:8002
TARGETING_SERVICE_URL=http://targeting-service:8003

# =============================================================================
# EXECUTION MODE
# =============================================================================
EXECUTION_MODE=${mode}
EOF

    success "Arquivo .env criado"
    
    # Retornar informações
    echo "$master_key"
    echo "$postgres_auth_user"
    echo "$postgres_flag_user"
    echo "$postgres_targeting_user"
}

# Função para atualizar .gitignore
update_gitignore() {
    if [ -f ".gitignore" ]; then
        if ! grep -q "^\.env$" .gitignore 2>/dev/null; then
            echo ".env" >> .gitignore
            echo ".env.backup.*" >> .gitignore
            echo "setup.log" >> .gitignore
            success ".env adicionado ao .gitignore"
        fi
    else
        cat > .gitignore << 'EOF'
# Environment files
.env
.env.backup.*
setup.log

# Keep example
!.env.example

# Docker volumes
postgres-*-data/
redis-data/
dynamodb-data/
localstack-data/

# OS files
.DS_Store
Thumbs.db

# IDE files
.vscode/
.idea/
*.swp
*.swo
*~
EOF
        success ".gitignore criado"
    fi
}

# =============================================================================
# FUNÇÃO PRINCIPAL
# =============================================================================

main() {
    # Inicializar log
    echo "=== Setup iniciado em $(date) ===" > "$LOG_FILE"
    
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}   ToggleMaster - Setup de Credenciais v2.1           ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Verificar se .env existe
    if [ -f ".env" ]; then
        warning "Arquivo .env já existe"
        echo ""
        echo -n "Deseja sobrescrever as credenciais existentes? (y/N): "
        read -r response
        
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            info "Setup cancelado pelo usuário"
            exit 0
        fi
        
    fi
    
    # Limpar ambiente Docker
    cleanup_docker_environment
    
    # Escolher ambiente
    echo ""
    echo -e "${CYAN}🌍 Escolha o ambiente de execução:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Local (Docker com LocalStack e DynamoDB Local)"
    echo -e "     ${BLUE}→${NC} Ideal para desenvolvimento e testes"
    echo -e "     ${BLUE}→${NC} Sem custos AWS"
    echo ""
    echo -e "  ${GREEN}2)${NC} AWS Real (SQS e DynamoDB na AWS)"
    echo -e "     ${BLUE}→${NC} Para produção ou testes com serviços reais"
    echo -e "     ${BLUE}→${NC} ${RED}Haverá cobrança pelos recursos utilizados${NC}"
    echo ""
    
    local env_choice=""
    while [[ ! "$env_choice" =~ ^[12]$ ]]; do
        echo -n "Selecione uma opção (1 ou 2): "
        read -r env_choice
        
        if [[ ! "$env_choice" =~ ^[12]$ ]]; then
            error "Opção inválida. Digite 1 ou 2."
        fi
    done
    
    local mode="local"
    local aws_access_key=""
    local aws_secret_key=""
    local aws_session_token=""
    local aws_region="us-east-1"
    local sqs_queue_url=""
    
    if [[ "$env_choice" == "2" ]]; then
        mode="aws"
        
        # Verificar AWS CLI
        if ! command -v aws &> /dev/null; then
            error "AWS CLI não está instalado!"
            echo ""
            echo "Por favor, instale o AWS CLI:"
            echo "  https://aws.amazon.com/cli/"
            exit 1
        fi
        
        echo ""
        info "Configurando modo AWS Real"
        echo ""
        
        # Perguntar sobre AWS Academy
        echo -n "Você está usando AWS Academy? (y/N): "
        read -r aws_academy_response
        
        local use_session_token=false
        if [[ "$aws_academy_response" =~ ^[Yy]$ ]]; then
            use_session_token=true
        fi
        
        echo ""
        info "Por favor, forneça suas credenciais AWS:"
        echo ""
        
        # Solicitar credenciais
        while [ -z "$aws_access_key" ]; do
            echo -n "AWS Access Key ID: "
            read -r aws_access_key
            [ -z "$aws_access_key" ] && error "Access Key não pode ser vazio"
        done
        
        while [ -z "$aws_secret_key" ]; do
            echo -n "AWS Secret Access Key: "
            read -rs aws_secret_key
            echo ""
            [ -z "$aws_secret_key" ] && error "Secret Key não pode ser vazio"
        done
        
        if [ "$use_session_token" = true ]; then
            while [ -z "$aws_session_token" ]; do
                echo -n "AWS Session Token: "
                read -r aws_session_token
                [ -z "$aws_session_token" ] && error "Session Token não pode ser vazio para AWS Academy"
            done
        fi
        
        echo ""
        echo -n "AWS Region (pressione Enter para us-east-1): "
        read -r region_input
        aws_region="${region_input:-us-east-1}"
        
        # Configurar credenciais temporariamente
        export AWS_ACCESS_KEY_ID="$aws_access_key"
        export AWS_SECRET_ACCESS_KEY="$aws_secret_key"
        export AWS_DEFAULT_REGION="$aws_region"
        
        if [ -n "$aws_session_token" ]; then
            export AWS_SESSION_TOKEN="$aws_session_token"
        fi
        
        # Criar recursos AWS
        local aws_output
        aws_output=$(create_aws_resources "$aws_region" 2>&1)
        local create_exit_code=$?
        
        # Limpar variáveis de ambiente
        unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_DEFAULT_REGION
        
        # Verificar se criação foi bem-sucedida
        if [ $create_exit_code -ne 0 ]; then
            error "Falha ao criar recursos AWS"
            echo "$aws_output" >&2
            exit 1
        fi
        
        # Extrair URL da última linha (que é onde a função retorna)
        sqs_queue_url=$(echo "$aws_output" | grep -o 'https://sqs[^[:space:]]*' | tail -1)
        
        # Validar que temos uma URL válida
        if [ -z "$sqs_queue_url" ]; then
            error "Não foi possível obter URL da fila SQS"
            echo "Output completo:"
            echo "$aws_output"
            exit 1
        fi
        
    else
        echo ""
        info "Configurando modo Local"
        
        # Gerar credenciais dummy
        aws_access_key="AKIA$(openssl rand -base64 12 | tr -d '/+=' | tr '[:lower:]' '[:upper:]' | cut -c1-16)"
        aws_secret_key=$(generate_token)
        aws_region="us-east-1"
        sqs_queue_url="http://localstack:4566/000000000000/togglemaster-events"
    fi
    
    echo ""
    
    # Criar arquivo .env
    local env_info
    env_info=$(create_env_file "$mode" "$aws_access_key" "$aws_secret_key" \
        "$aws_session_token" "$aws_region" "$sqs_queue_url")
    
    local master_key=$(echo "$env_info" | sed -n '1p')
    local postgres_auth_user=$(echo "$env_info" | sed -n '2p')
    local postgres_flag_user=$(echo "$env_info" | sed -n '3p')
    local postgres_targeting_user=$(echo "$env_info" | sed -n '4p')
    
    # Atualizar .gitignore
    update_gitignore
    
    # Resumo final
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  🎉 Setup concluído com sucesso! 🎉                   ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ "$mode" = "aws" ]; then
        echo -e "${CYAN}☁️  Modo: AWS Real${NC}"
        echo ""
        echo -e "${GREEN}Recursos AWS criados/verificados:${NC}"
        echo -e "  ${BLUE}•${NC} Região: ${aws_region}"
        echo -e "  ${BLUE}•${NC} Tabela DynamoDB: ToggleMasterAnalytics"
        echo -e "  ${BLUE}•${NC} Fila SQS: togglemaster-events"
        echo -e "  ${BLUE}•${NC} URL da Fila: ${sqs_queue_url}"
    else
        echo -e "${CYAN}🏠 Modo: Local (Docker)${NC}"
        echo ""
        echo -e "${GREEN}Serviços locais que serão usados:${NC}"
        echo -e "  ${BLUE}•${NC} LocalStack (emulação SQS)"
        echo -e "  ${BLUE}•${NC} DynamoDB Local"
    fi
    
    echo ""
    echo -e "${YELLOW}📝 Credenciais geradas:${NC}"
    echo ""
    echo -e "  ${BLUE}Master Key:${NC} ${master_key:0:20}..."
    echo -e "  ${BLUE}PostgreSQL Auth:${NC} ${postgres_auth_user}"
    echo -e "  ${BLUE}PostgreSQL Flag:${NC} ${postgres_flag_user}"
    echo -e "  ${BLUE}PostgreSQL Targeting:${NC} ${postgres_targeting_user}"
    echo -e "  ${BLUE}Redis:${NC} [senha gerada]"
    echo ""
    echo -e "${YELLOW}⚠️  IMPORTANTE:${NC}"
    echo -e "  ${RED}1.${NC} Volumes Docker foram limpos"
    echo -e "  ${RED}2.${NC} ${RED}NUNCA${NC} faça commit do arquivo ${GREEN}.env${NC}"
    echo -e "  ${RED}3.${NC} Use ${GREEN}.env.example${NC} como referência"
    echo -e "  ${RED}4.${NC} Gere a SERVICE_API_KEY conforme o README"
    echo ""
    echo -e "${GREEN}✅ Próximo passo:${NC} ./togglemaster.sh start"
    echo ""
    
    if [ "$mode" = "aws" ]; then
        echo -e "${PURPLE}💡 Para deletar recursos AWS:${NC}"
        echo ""
        echo "  aws dynamodb delete-table --table-name ToggleMasterAnalytics --region ${aws_region}"
        echo "  aws sqs delete-queue --queue-url ${sqs_queue_url} --region ${aws_region}"
        echo ""
    fi
    
    log "Setup concluído com sucesso"
}

# Executar função principal
main "$@"
