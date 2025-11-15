#!/bin/bash

echo "🚀 SETUP AWS SQS - TOGGLEMASTER"
echo "================================"
echo ""

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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
    source .env
else
    echo -e "${RED}❌ Arquivo .env não encontrado!${NC}"
    exit 1
fi

# Verificar credenciais
if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo -e "${RED}❌ AWS_ACCESS_KEY_ID não definida no .env${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Credenciais AWS carregadas"
echo ""

# Configurar região
export AWS_DEFAULT_REGION=us-east-1

echo "📍 Região: us-east-1 (Norte da Virgínia)"
echo ""

# Testar credenciais
echo "🔐 Testando credenciais AWS..."
if aws sts get-caller-identity &> /dev/null; then
    echo -e "${GREEN}✓${NC} Credenciais válidas!"
    aws sts get-caller-identity
    echo ""
else
    echo -e "${RED}❌ Credenciais inválidas ou expiradas!${NC}"
    echo "Gere novas credenciais temporárias e atualize o .env"
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
    sed -i.bak "s|SQS_QUEUE_URL=.*|SQS_QUEUE_URL=$QUEUE_URL|" .env
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
        sed -i.bak "s|SQS_QUEUE_URL=.*|SQS_QUEUE_URL=$QUEUE_URL|" .env
        echo -e "${GREEN}✓${NC} Arquivo .env atualizado"
        echo ""
    else
        echo -e "${RED}❌ Erro ao criar/obter fila SQS${NC}"
        exit 1
    fi
fi

# Testar envio de mensagem
echo "📤 Testando envio de mensagem..."

TEST_MESSAGE='{"event":"setup_test","timestamp":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}'

if aws sqs send-message \
    --queue-url "$QUEUE_URL" \
    --message-body "$TEST_MESSAGE" \
    --region us-east-1 &> /dev/null; then
    echo -e "${GREEN}✓${NC} Mensagem de teste enviada com sucesso!"
    echo ""
else
    echo -e "${RED}❌ Erro ao enviar mensagem de teste${NC}"
    exit 1
fi

# Ver atributos da fila
echo "📊 Atributos da fila:"
aws sqs get-queue-attributes \
    --queue-url "$QUEUE_URL" \
    --attribute-names ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible,VisibilityTimeout \
    --region us-east-1 \
    --output table

echo ""
echo -e "${GREEN}🎉 SETUP COMPLETO!${NC}"
echo ""
echo "📋 Próximos passos:"
echo "   2. Subir os serviços: ./togglemaster.sh start"
echo "   3. Verificar logs: ./togglemaster.sh logs"
echo "   4. Teste as APIs: ./togglemaster.sh test
echo ""
echo "🔗 URL da Fila SQS:"
echo "   $QUEUE_URL"
echo ""
echo "✅ Tudo pronto para usar AWS SQS real!"
