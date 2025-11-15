#!/bin/bash

echo "🧹 RESET COMPLETO DO TOGGLEMASTER"
echo "=================================="
echo ""

echo "1. Parando todos os containers..."
docker-compose down
echo "✓ Containers parados"
echo ""

echo "2. Removendo volumes (limpa dados)..."
docker-compose down -v
echo "✓ Volumes removidos"
echo ""

echo "3. Removendo imagens antigas..."
docker-compose down --rmi local
echo "✓ Imagens removidas"
echo ""

echo "4. Limpando cache do Docker..."
docker system prune -f
echo "✓ Cache limpo"
echo ""

echo "5. Rebuilding todas as imagens (pode levar alguns minutos)..."
docker-compose build --no-cache
echo "✓ Imagens reconstruídas"
echo ""

echo "6. Subindo serviços..."
docker-compose up -d
echo "✓ Serviços iniciados"
echo ""

echo "7. Aguardando inicialização (120 segundos)..."
for i in {1..120}; do
    echo -ne "\r⏱️  Aguardando... $i/120 segundos"
    sleep 1
done
echo ""
echo "✓ Tempo de espera concluído"
echo ""

echo "8. Verificando status..."
docker-compose ps
echo ""

echo "9. Health check..."
./togglemaster.sh health
echo ""

echo "🎉 RESET COMPLETO!"
echo ""
echo "📋 Próximos passos:"
echo "   - Verifique os logs: ./togglemaster.sh logs"
echo "   - Teste as APIs: ./togglemaster.sh test"
echo ""
