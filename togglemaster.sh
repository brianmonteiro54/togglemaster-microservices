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
NC='\033[0m' # No Color

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
    
  💾 Backup e Dados:
    backup          Cria backup dos volumes de dados
    restore         Restaura backup dos volumes
    
  📈 Informações:
    info            Informações sobre recursos utilizados
    ports           Lista portas mapeadas
    network         Informações sobre a rede

Exemplos:
  ./togglemaster.sh start
  ./togglemaster.sh logs auth-service
  ./togglemaster.sh health
  ./togglemaster.sh clean-all

EOF
}

# Função para iniciar serviços
start_services() {
    print_info "Iniciando ToggleMaster..."
    docker-compose up -d
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
    docker-compose restart
    print_success "Serviços reiniciados!"
}

# Função para rebuild
rebuild_services() {
    print_warning "Rebuild completo (isso pode demorar)..."
    docker-compose down
    docker-compose build --no-cache
    docker-compose up -d
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
    
    # Teste 1: Verificar se todos os containers estão rodando
    print_info "Teste 1: Verificando containers..."
    if [ "$(docker-compose ps -q | wc -l)" -ge 10 ]; then
        print_success "Todos os containers estão rodando"
    else
        print_error "Alguns containers não estão rodando"
    fi
    
    # Teste 2: Verificar conectividade dos bancos
    print_info "Teste 2: Verificando PostgreSQL..."
    if docker-compose exec -T postgres-auth pg_isready -U authuser > /dev/null 2>&1; then
        print_success "PostgreSQL Auth - OK"
    else
        print_error "PostgreSQL Auth - FALHOU"
    fi
    
    # Teste 3: Verificar Redis
    print_info "Teste 3: Verificando Redis..."
    if docker-compose exec -T redis redis-cli -a redispass123 ping > /dev/null 2>&1; then
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
        docker-compose config --services
    else
        print_error "Configuração inválida!"
        exit 1
    fi
}

# Função para limpeza
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

clean_containers() {
    print_info "Removendo containers e networks..."
    docker-compose down
    print_success "Containers e networks removidos!"
}

# Função para prune
prune_docker() {
    print_info "Limpando recursos Docker não utilizados..."
    docker system prune -f
    print_success "Prune concluído!"
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
  - LocalStack SQS:      localhost:4566
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
        prune)
            prune_docker
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
