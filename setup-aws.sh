#!/bin/bash

echo "🚀 SETUP AWS SQS - TOGGLEMASTER"
echo "================================"
echo ""

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Verificar se AWS CLI está instalado
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI não encontrado!${NC}"
    echo "Instale com: curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip' && unzip awscliv2.zip && sudo ./aws/install"
    exit 1
fi

echo -e "${GREEN}✓${NC} AWS CLI encontrado"
echo ""

# Carregar variáveis do .env
if [ -f .env ]; then
    echo -e "${GREEN}✓${NC} Arquivo .env encontrado"
    echo ""
    
    # ⚠️ SOLUÇÃO: Usar set -a para exportar automaticamente todas as variáveis
    # Isso garante que as variáveis fiquem disponíveis para o AWS CLI sem precisar do ~/.aws/credentials
    echo -e "${BLUE}📋 Carregando e exportando variáveis do .env...${NC}"
    set -a  # Ativa exportação automática de variáveis
    source .env
    set +a  # Desativa exportação automática
    
    # Exportar explicitamente as variáveis AWS (redundante mas garante)
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    export AWS_SESSION_TOKEN
    export AWS_REGION="us-east-1"
    export AWS_DEFAULT_REGION="us-east-1"
    
    echo -e "${GREEN}✓${NC} Variáveis exportadas para o ambiente"
    echo ""
else
    echo -e "${RED}❌ Arquivo .env não encontrado!${NC}"
    echo "Crie um arquivo .env com as credenciais AWS"
    exit 1
fi

# Verificar se as credenciais foram carregadas
if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo -e "${RED}❌ AWS_ACCESS_KEY_ID não definida no .env${NC}"
    exit 1
fi

if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo -e "${RED}❌ AWS_SECRET_ACCESS_KEY não definida no .env${NC}"
    exit 1
fi

# Mostrar as credenciais mascaradas (para debug)
echo -e "${BLUE}🔑 Credenciais carregadas:${NC}"
echo "   AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:10}..."
echo "   AWS_SECRET_ACCESS_KEY: ****"
if [ -n "$AWS_SESSION_TOKEN" ]; then
    echo "   AWS_SESSION_TOKEN: ${AWS_SESSION_TOKEN:0:20}..."
fi
echo ""

echo -e "${GREEN}✓${NC} Credenciais AWS carregadas e exportadas"
echo ""

# Configurar região
echo "📍 Região: us-east-1 (Norte da Virgínia)"
echo ""

# Testar credenciais
echo "🔐 Testando credenciais AWS..."
echo -e "${YELLOW}⏳ Executando: aws sts get-caller-identity${NC}"
echo ""

# Usar as variáveis de ambiente diretamente (não depende de ~/.aws/credentials)
if AWS_OUTPUT=$(aws sts get-caller-identity 2>&1); then
    echo -e "${GREEN}✓${NC} Credenciais válidas!"
    echo "$AWS_OUTPUT" | jq . 2>/dev/null || echo "$AWS_OUTPUT"
    echo ""
else
    echo -e "${RED}❌ Credenciais inválidas ou expiradas!${NC}"
    echo ""
    echo "Detalhes do erro:"
    echo "$AWS_OUTPUT"
    echo ""
    echo "💡 Possíveis causas:"
    echo "   1. Credenciais expiradas (credenciais temporárias duram 4 horas)"
    echo "   2. Credenciais incorretas no .env"
    echo "   3. Região AWS incorreta"
    echo ""
    echo "🔧 Solução:"
    echo "   1. Gere novas credenciais temporárias no AWS Academy"
    echo "   2. Atualize o arquivo .env com as novas credenciais"
    echo "   3. Execute novamente: ./setup-aws.sh"
    exit 1
fi

# Criar fila SQS
echo "📨 Criando fila SQS 'togglemaster-events'..."

QUEUE_URL=$(aws sqs create-queue \
    --queue-name togglemaster-events \
    --region us-east-1 \
    --attributes '{
        "VisibilityTimeout": "300",
        "MessageRetentionPeriod": "345600",
        "ReceiveMessageWaitTimeSeconds": "20"
    }' \
    --query 'QueueUrl' \
    --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$QUEUE_URL" ]; then
    echo -e "${GREEN}✓${NC} Fila criada com sucesso!"
    echo "URL: $QUEUE_URL"
    echo ""
    
    # Atualizar .env com a URL da fila
    # Remove backup antigo se existir
    [ -f .env.bak ] && rm .env.bak
    
    # Atualiza ou adiciona a variável SQS_QUEUE_URL
    if grep -q "^SQS_QUEUE_URL=" .env; then
        sed -i.bak "s|^SQS_QUEUE_URL=.*|SQS_QUEUE_URL=$QUEUE_URL|" .env
    else
        echo "" >> .env
        echo "# URL da fila SQS criada automaticamente" >> .env
        echo "SQS_QUEUE_URL=$QUEUE_URL" >> .env
    fi
    rm -f .env.bak
    echo -e "${GREEN}✓${NC} Arquivo .env atualizado"
    echo ""
else
    # Fila já existe, tentar obter URL
    echo -e "${YELLOW}⚠${NC}  Fila já existe, obtendo URL..."
    
    QUEUE_URL=$(aws sqs get-queue-url \
        --queue-name togglemaster-events \
        --region us-east-1 \
        --query 'QueueUrl' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$QUEUE_URL" ]; then
        echo -e "${GREEN}✓${NC} URL da fila obtida!"
        echo "URL: $QUEUE_URL"
        echo ""
        
        # Atualizar .env
        [ -f .env.bak ] && rm .env.bak
        
        if grep -q "^SQS_QUEUE_URL=" .env; then
            sed -i.bak "s|^SQS_QUEUE_URL=.*|SQS_QUEUE_URL=$QUEUE_URL|" .env
        else
            echo "" >> .env
            echo "# URL da fila SQS criada automaticamente" >> .env
            echo "SQS_QUEUE_URL=$QUEUE_URL" >> .env
        fi
        
        echo -e "${GREEN}✓${NC} Arquivo .env atualizado"
        echo ""
    else
        echo -e "${RED}❌ Erro ao criar/obter fila SQS${NC}"
        exit 1
    fi
fi

# # Testar envio de mensagem
# echo "📤 Testando envio de mensagem..."

# TEST_MESSAGE='{"event":"setup_test","timestamp":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}'

# if aws sqs send-message \
#     --queue-url "$QUEUE_URL" \
#     --message-body "$TEST_MESSAGE" \
#     --region us-east-1 &> /dev/null; then
#     echo -e "${GREEN}✓${NC} Mensagem de teste enviada com sucesso!"
#     echo ""
# else
#     echo -e "${RED}❌ Erro ao enviar mensagem de teste${NC}"
#     echo "A fila foi criada, mas não foi possível enviar mensagem"
#     echo ""
# fi

# Ver atributos da fila
echo "📊 Atributos da fila:"
aws sqs get-queue-attributes \
    --queue-url "$QUEUE_URL" \
    --attribute-names ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible,VisibilityTimeout \
    --region us-east-1 \
    --output table 2>/dev/null || echo "Fila criada mas sem mensagens ainda"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}🎉 SETUP COMPLETO!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "🔗 Informações da Fila SQS:"
echo "   Nome: togglemaster-events"
echo "   URL: $QUEUE_URL"
echo "   Região: us-east-1"
echo ""
echo "💡 Dicas importantes:"
echo "   • As credenciais temporárias expiram em 4 horas"
echo "   • Para renovar, gere novas credenciais no AWS Academy"
