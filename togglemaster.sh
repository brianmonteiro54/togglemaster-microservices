#!/bin/bash

# =============================================================================
# ToggleMaster - Script Helper
# =============================================================================
# Script utilitário para gerenciar o ambiente Docker do ToggleMaster
# =============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Diretório de backups
BACKUP_DIR="./backups"

# Funções auxiliares
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Função para verificar se o Docker está rodando
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker não está rodando!"
        exit 1
    fi
}

# Função para detectar modo de execução
detect_execution_mode() {
    if [ ! -f ".env" ]; then
        print_warning "Arquivo .env não encontrado!"
        print_info "Execute ./setup-credentials.sh primeiro"
        return 1
    fi
    
    local mode=$(grep "^EXECUTION_MODE=" .env | cut -d'=' -f2)
    echo "$mode"
}

# Função de ajuda
show_help() {
    cat << EOF
╔══════════════════════════════════════════════════════════════════╗
║          ToggleMaster - Script de Gerenciamento                  ║
╚══════════════════════════════════════════════════════════════════╝

Uso: ./togglemaster.sh [comando]

Comandos Disponíveis:

  📦 Gerenciamento de Containers:
    start           Inicia todos os serviços
    stop            Para todos os serviços
    restart         Reinicia todos os serviços
    rebuild         Rebuild completo (sem cache)
    
  📊 Monitoramento:
    status          Mostra status de todos os containers
    logs            Exibe logs de todos os serviços
    logs [service]  Exibe logs de um serviço específico
    health          Verifica health de todos os endpoints
    
  🧪 Testes e Validação:
    test            Executa testes básicos de conectividade
    validate        Valida configuração do docker-compose
    
  🔧 Manutenção:
    clean           Remove containers e networks (mantém volumes)
    clean-all       Remove tudo (containers, networks, volumes, images)
    prune           Limpa recursos Docker não utilizados
    reset-db        Reseta apenas bancos PostgreSQL
    
  💾 Backup e Dados:
    backup          Cria backup dos volumes de dados
    backup [nome]   Cria backup com nome personalizado
    restore         Restaura último backup
    restore [nome]  Restaura backup específico
    list-backups    Lista todos os backups disponíveis
    
  📈 Informações:
    info            Informações sobre recursos utilizados
    ports           Lista portas mapeadas
    network         Informações sobre a rede
    mode            Mostra modo de execução atual (local/aws)

Exemplos:
  ./togglemaster.sh start
  ./togglemaster.sh logs
  ./togglemaster.sh health
  ./togglemaster.sh backup
  ./togglemaster.sh restore

EOF
}

# Função para iniciar serviços
start_services() {
    print_info "Iniciando ToggleMaster..."
    
    # Detectar modo de execução
    local mode=$(detect_execution_mode)
    
    if [ -z "$mode" ]; then
        print_error "Não foi possível detectar o modo de execução"
        print_info "Execute ./setup-credentials.sh primeiro"
        exit 1
    fi
    
    echo ""
    if [ "$mode" = "aws" ]; then
        print_info "Modo detectado: AWS Real ☁️"
        print_warning "LocalStack e DynamoDB Local NÃO serão iniciados"
        echo ""
        COMPOSE_PROFILES="" docker-compose up -d
    else
        print_info "Modo detectado: Local 🏠"
        print_info "Iniciando com LocalStack e DynamoDB Local"
        echo ""
        COMPOSE_PROFILES="local" docker-compose up -d
    fi
    
    print_success "Serviços iniciados!"
    echo ""
    print_info "Aguarde alguns segundos para os serviços ficarem prontos..."
    sleep 10
    check_health
}

# Função para parar serviços
stop_services() {
    print_info "Parando ToggleMaster..."
    docker-compose down
    print_success "Serviços parados!"
}

# Função para reiniciar serviços
restart_services() {
    print_info "Reiniciando ToggleMaster..."
    
    local mode=$(detect_execution_mode)
    
    if [ "$mode" = "aws" ]; then
        COMPOSE_PROFILES="" docker-compose restart
    else
        COMPOSE_PROFILES="local" docker-compose restart
    fi
    
    print_success "Serviços reiniciados!"
}

# Função para rebuild
rebuild_services() {
    print_warning "Rebuild completo (isso pode demorar)..."
    
    local mode=$(detect_execution_mode)
    
    docker-compose down
    docker-compose build --no-cache
    
    if [ "$mode" = "aws" ]; then
        COMPOSE_PROFILES="" docker-compose up -d
    else
        COMPOSE_PROFILES="local" docker-compose up -d
    fi
    
    print_success "Rebuild concluído!"
}

# Função para mostrar status
show_status() {
    print_info "Status dos Containers:"
    docker-compose ps
}

# Função para mostrar logs
show_logs() {
    if [ -z "$1" ]; then
        print_info "Logs de todos os serviços (Ctrl+C para sair):"
        docker-compose logs -f --tail=100
    else
        print_info "Logs do serviço: $1"
        docker-compose logs -f --tail=100 "$1"
    fi
}

# Função para verificar health
check_health() {
    print_info "Verificando health dos serviços..."
    echo ""
    
    services=("auth-service:8001" "flag-service:8002" "targeting-service:8003" "evaluation-service:8004" "analytics-service:8005")
    
    for service in "${services[@]}"; do
        IFS=':' read -r name port <<< "$service"
        if curl -sf "http://localhost:$port/health" > /dev/null 2>&1; then
            print_success "$name (porta $port) - HEALTHY"
        else
            print_error "$name (porta $port) - UNHEALTHY"
        fi
    done
    echo ""
}

# Função para executar testes básicos
run_tests() {
    print_info "Executando testes básicos..."
    echo ""
    
    local mode=$(detect_execution_mode)
    
    # Teste 1: Verificar se todos os containers estão rodando
    print_info "Teste 1: Verificando containers..."
    local expected_containers=8
    [ "$mode" = "local" ] && expected_containers=13
    
    local running=$(docker-compose ps -q | wc -l)
    if [ "$running" -ge "$expected_containers" ]; then
        print_success "Containers rodando: $running"
    else
        print_error "Esperado: $expected_containers, Rodando: $running"
    fi
    
    # Teste 2: Verificar conectividade dos bancos
    print_info "Teste 2: Verificando PostgreSQL..."
    
    local auth_user=$(grep "^POSTGRES_AUTH_USER=" .env | cut -d'=' -f2)
    local flag_user=$(grep "^POSTGRES_FLAG_USER=" .env | cut -d'=' -f2)
    local target_user=$(grep "^POSTGRES_TARGETING_USER=" .env | cut -d'=' -f2)
    
    if docker-compose exec -T postgres-auth pg_isready -U "$auth_user" > /dev/null 2>&1; then
        print_success "PostgreSQL Auth - OK"
    else
        print_error "PostgreSQL Auth - FALHOU"
    fi
    
    if docker-compose exec -T postgres-flag pg_isready -U "$flag_user" > /dev/null 2>&1; then
        print_success "PostgreSQL Flag - OK"
    else
        print_error "PostgreSQL Flag - FALHOU"
    fi
    
    if docker-compose exec -T postgres-targeting pg_isready -U "$target_user" > /dev/null 2>&1; then
        print_success "PostgreSQL Targeting - OK"
    else
        print_error "PostgreSQL Targeting - FALHOU"
    fi
    
    # Teste 3: Verificar Redis
    print_info "Teste 3: Verificando Redis..."
    local redis_pass=$(grep "^REDIS_PASSWORD=" .env | cut -d'=' -f2)
    
    if docker-compose exec -T redis redis-cli -a "$redis_pass" ping 2>/dev/null | grep -q "PONG"; then
        print_success "Redis - OK"
    else
        print_error "Redis - FALHOU"
    fi
    
    # Teste 4: Health endpoints
    print_info "Teste 4: Verificando health endpoints..."
    check_health
    
    print_success "Testes concluídos!"
}

# Função para validar docker-compose
validate_compose() {
    print_info "Validando configuração do docker-compose.yml..."
    if docker-compose config > /dev/null 2>&1; then
        print_success "Configuração válida!"
        echo ""
        print_info "Serviços configurados:"
        docker-compose config --services
    else
        print_error "Configuração inválida!"
        exit 1
    fi
}

# Função para limpeza completa
clean_all() {
    print_warning "Esta operação removerá TODOS os dados. Deseja continuar? (yes/no)"
    read -r response
    if [ "$response" = "yes" ]; then
        print_info "Removendo tudo..."
        docker-compose down -v --rmi all
        print_success "Limpeza completa realizada!"
    else
        print_info "Operação cancelada"
    fi
}

# Função para limpeza de containers
clean_containers() {
    print_info "Removendo containers e networks..."
    docker-compose down
    print_success "Containers e networks removidos!"
}

# Função para resetar bancos PostgreSQL
reset_databases() {
    print_warning "Esta operação removerá TODOS os dados dos bancos PostgreSQL!"
    print_warning "Deseja continuar? (yes/no)"
    read -r response
    
    if [ "$response" = "yes" ]; then
        print_info "Parando containers..."
        docker-compose down
        
        print_info "Removendo volumes PostgreSQL..."
        docker volume rm togglemaster-postgres-auth-data 2>/dev/null && print_success "Volume auth removido" || print_warning "Volume auth não existe"
        docker volume rm togglemaster-postgres-flag-data 2>/dev/null && print_success "Volume flag removido" || print_warning "Volume flag não existe"
        docker volume rm togglemaster-postgres-targeting-data 2>/dev/null && print_success "Volume targeting removido" || print_warning "Volume targeting não existe"
        
        print_success "Bancos resetados! Execute './togglemaster.sh start' para recriar"
    else
        print_info "Operação cancelada"
    fi
}

# Função para prune
prune_docker() {
    print_info "Limpando recursos Docker não utilizados..."
    docker system prune -f
    print_success "Prune concluído!"
}

# Função para criar backup
create_backup() {
    local backup_name="${1:-backup-$(date +%Y%m%d-%H%M%S)}"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    # Criar diretório de backup se não existir
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$backup_path"
    
    print_info "Criando backup: $backup_name"
    echo ""
    
    # Volumes para backup
    local volumes=(
        "togglemaster-postgres-auth-data"
        "togglemaster-postgres-flag-data"
        "togglemaster-postgres-targeting-data"
        "togglemaster-redis-data"
        "togglemaster-dynamodb-data"
        "togglemaster-localstack-data"
    )
    
    for volume in "${volumes[@]}"; do
        if docker volume inspect "$volume" > /dev/null 2>&1; then
            print_info "Fazendo backup de: $volume"
            
            # Criar backup usando um container temporário
            docker run --rm \
                -v "$volume:/data" \
                -v "$(pwd)/$backup_path:/backup" \
                alpine:latest \
                tar czf "/backup/${volume}.tar.gz" -C /data . 2>/dev/null
            
            if [ -f "$backup_path/${volume}.tar.gz" ]; then
                local size=$(du -h "$backup_path/${volume}.tar.gz" | cut -f1)
                print_success "$volume - $size"
            else
                print_warning "$volume - não criado"
            fi
        else
            print_warning "$volume - não existe"
        fi
    done
    
    # Criar backup do .env
    if [ -f ".env" ]; then
        cp .env "$backup_path/.env.backup"
        print_success ".env copiado"
    fi
    
    # Criar arquivo de metadados
    cat > "$backup_path/metadata.txt" << EOF
Backup criado em: $(date)
Hostname: $(hostname)
Modo de execução: $(detect_execution_mode)
Docker Compose versão: $(docker-compose version --short)
EOF
    
    echo ""
    print_success "Backup criado em: $backup_path"
    echo ""
    print_info "Para restaurar este backup, execute:"
    print_info "  ./togglemaster.sh restore $backup_name"
}

# Função para restaurar backup
restore_backup() {
    local backup_name="$1"
    
    # Se não especificado, pegar o mais recente
    if [ -z "$backup_name" ]; then
        backup_name=$(ls -t "$BACKUP_DIR" 2>/dev/null | head -1)
        if [ -z "$backup_name" ]; then
            print_error "Nenhum backup encontrado em $BACKUP_DIR"
            exit 1
        fi
        print_info "Usando backup mais recente: $backup_name"
    fi
    
    local backup_path="$BACKUP_DIR/$backup_name"
    
    if [ ! -d "$backup_path" ]; then
        print_error "Backup não encontrado: $backup_path"
        exit 1
    fi
    
    print_warning "Esta operação substituirá os dados atuais!"
    print_warning "Deseja continuar? (yes/no)"
    read -r response
    
    if [ "$response" != "yes" ]; then
        print_info "Operação cancelada"
        exit 0
    fi
    
    print_info "Restaurando backup: $backup_name"
    echo ""
    
    # Parar containers
    print_info "Parando containers..."
    docker-compose down
    
    # Restaurar volumes
    for archive in "$backup_path"/*.tar.gz; do
        if [ -f "$archive" ]; then
            local volume_name=$(basename "$archive" .tar.gz)
            
            print_info "Restaurando: $volume_name"
            
            # Remover volume existente
            docker volume rm "$volume_name" 2>/dev/null || true
            
            # Criar volume novo
            docker volume create "$volume_name" > /dev/null
            
            # Restaurar dados
            docker run --rm \
                -v "$volume_name:/data" \
                -v "$(pwd)/$backup_path:/backup" \
                alpine:latest \
                tar xzf "/backup/$(basename "$archive")" -C /data 2>/dev/null
            
            print_success "$volume_name restaurado"
        fi
    done
    
    # Restaurar .env se existir no backup
    if [ -f "$backup_path/.env.backup" ]; then
        print_info "Restaurar arquivo .env também? (y/N)"
        read -r restore_env
        if [[ "$restore_env" =~ ^[Yy]$ ]]; then
            cp "$backup_path/.env.backup" .env
            print_success ".env restaurado"
        fi
    fi
    
    echo ""
    print_success "Backup restaurado!"
    print_info "Execute './togglemaster.sh start' para iniciar os serviços"
}

# Função para listar backups
list_backups() {
    print_info "Backups disponíveis em: $BACKUP_DIR"
    echo ""
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        print_warning "Nenhum backup encontrado"
        return
    fi
    
    printf "%-30s %-20s %-10s\n" "NOME" "DATA" "TAMANHO"
    echo "────────────────────────────────────────────────────────────"
    
    for backup in "$BACKUP_DIR"/*; do
        if [ -d "$backup" ]; then
            local name=$(basename "$backup")
            local date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$backup" 2>/dev/null || stat -c "%y" "$backup" | cut -d' ' -f1,2)
            local size=$(du -sh "$backup" 2>/dev/null | cut -f1)
            
            printf "%-30s %-20s %-10s\n" "$name" "$date" "$size"
        fi
    done
    
    echo ""
    print_info "Para restaurar um backup:"
    print_info "  ./togglemaster.sh restore [nome-do-backup]"
}

# Função para mostrar modo
show_mode() {
    local mode=$(detect_execution_mode)
    
    if [ -z "$mode" ]; then
        print_error "Não foi possível detectar o modo"
        exit 1
    fi
    
    echo ""
    if [ "$mode" = "aws" ]; then
        print_info "Modo de Execução: AWS Real ☁️"
        echo ""
        echo "  • DynamoDB: AWS Real"
        echo "  • SQS: AWS Real"
        local sqs_url=$(grep "^SQS_QUEUE_URL=" .env | cut -d'=' -f2)
        echo "  • Fila SQS: $sqs_url"
    else
        print_info "Modo de Execução: Local 🏠"
        echo ""
        echo "  • DynamoDB: Local (porta 8000)"
        echo "  • SQS: LocalStack (porta 4566)"
        echo "  • Fila SQS: http://localstack:4566/000000000000/togglemaster-events"
    fi
    echo ""
}

# Função para mostrar informações
show_info() {
    print_info "Informações do Sistema:"
    echo ""
    echo "📦 Containers:"
    docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    echo "💾 Volumes:"
    docker volume ls --filter name=togglemaster
    echo ""
    echo "📊 Uso de Recursos:"
    docker stats --no-stream
}

# Função para listar portas
show_ports() {
    print_info "Portas Mapeadas:"
    echo ""
    cat << EOF
Serviços:
  - Auth Service:       http://localhost:8001
  - Flag Service:       http://localhost:8002
  - Targeting Service:  http://localhost:8003
  - Evaluation Service: http://localhost:8004
  - Analytics Service:  http://localhost:8005

Bancos de Dados:
  - PostgreSQL Auth:      localhost:5432
  - PostgreSQL Flag:      localhost:5433
  - PostgreSQL Targeting: localhost:5434
  - Redis:               localhost:6379
  - DynamoDB Local:      localhost:8000
  - LocalStack:          localhost:4566
EOF
}

# Função para mostrar info da rede
show_network() {
    print_info "Informações da Rede:"
    docker network inspect togglemaster-network
}

# Main
main() {
    check_docker
    
    case "${1:-}" in
        start)
            start_services
            ;;
        stop)
            stop_services
            ;;
        restart)
            restart_services
            ;;
        rebuild)
            rebuild_services
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs "$2"
            ;;
        health)
            check_health
            ;;
        test)
            run_tests
            ;;
        validate)
            validate_compose
            ;;
        clean)
            clean_containers
            ;;
        clean-all)
            clean_all
            ;;
        reset-db)
            reset_databases
            ;;
        prune)
            prune_docker
            ;;
        backup)
            create_backup "$2"
            ;;
        restore)
            restore_backup "$2"
            ;;
        list-backups)
            list_backups
            ;;
        mode)
            show_mode
            ;;
        info)
            show_info
            ;;
        ports)
            show_ports
            ;;
        network)
            show_network
            ;;
        help|--help|-h|"")
            show_help
            ;;
        *)
            print_error "Comando desconhecido: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"