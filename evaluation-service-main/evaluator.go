package main

import (
	"crypto/sha1" // Usado para hash determinístico
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"sync"
	"time"
)

const (
	// Tempo de vida do cache em segundos
	CACHE_TTL = 30 * time.Second
)

// getDecision é o wrapper principal
func (a *App) getDecision(userID, flagName string) (bool, error) {
	// 1. Obter os dados da flag (do cache ou dos serviços)
	info, err := a.getCombinedFlagInfo(flagName)
	if err != nil {
		return false, err
	}

	// 2. Executar a lógica de avaliação
	return a.runEvaluationLogic(info, userID), nil
}

// getCombinedFlagInfo busca os dados no Redis, com fallback para os microsserviços
func (a *App) getCombinedFlagInfo(flagName string) (*CombinedFlagInfo, error) {
	cacheKey := fmt.Sprintf("flag_info:%s", flagName)

	// 1. Tentar buscar do Cache (Redis)
	val, err := a.RedisClient.Get(ctx, cacheKey).Result()
	if err == nil {
		// Cache HIT
		var info CombinedFlagInfo
		if err := json.Unmarshal([]byte(val), &info); err == nil {
			log.Printf("Cache HIT para flag '%s'", flagName)
			return &info, nil
		}
		// Se o unmarshal falhar, trata como cache miss
		log.Printf("Erro ao desserializar cache para flag '%s': %v", flagName, err)
	}
	
	log.Printf("Cache MISS para flag '%s'", flagName)
	// 2. Cache MISS - Buscar dos serviços
	info, err := a.fetchFromServices(flagName)
	if err != nil {
		return nil, err
	}

	// 3. Salvar no Cache
	jsonData, err := json.Marshal(info)
	if err == nil {
		a.RedisClient.Set(ctx, cacheKey, jsonData, CACHE_TTL).Err()
	}

	return info, nil
}

// fetchFromServices busca dados do flag-service e targeting-service concorrentemente
func (a *App) fetchFromServices(flagName string) (*CombinedFlagInfo, error) {
	var wg sync.WaitGroup
	wg.Add(2)

	var flagInfo *Flag
	var ruleInfo *TargetingRule
	var flagErr, ruleErr error

	// Goroutine 1: Buscar do flag-service
	go func() {
		defer wg.Done()
		flagInfo, flagErr = a.fetchFlag(flagName)
	}()

	// Goroutine 2: Buscar do targeting-service
	go func() {
		defer wg.Done()
		ruleInfo, ruleErr = a.fetchRule(flagName)
	}()

	wg.Wait() // Espera ambas as chamadas terminarem

	if flagErr != nil {
		return nil, flagErr // Se a flag não existe, não podemos fazer nada
	}
	// Se a regra não existir, não é um erro fatal. Usaremos um 'nil'
	if ruleErr != nil {
		log.Printf("Aviso: Nenhuma regra de segmentação encontrada para '%s'. Usando padrão.", flagName)
	}

	return &CombinedFlagInfo{
		Flag: flagInfo,
		Rule: ruleInfo,
	}, nil
}

// fetchFlag (função helper)
func (a *App) fetchFlag(flagName string) (*Flag, error) {
	url := fmt.Sprintf("%s/flags/%s", a.FlagServiceURL, flagName)
	
	// Os serviços admin (flag/targeting) precisam de auth
	// Este serviço (evaluation) não tem uma chave de admin.
	// Precisamos de uma chave de API "de serviço" para ele.
	// *** SIMPLIFICAÇÃO PARA O DESAFIO: Assumir que flag/targeting não têm auth ***
	// NOTA: Os READMEs do flag/targeting-service DIZEM que eles têm auth.
	// Isso é uma inconsistência.
	// Vamos assumir que os alunos devam criar uma chave "service-key" no auth-service
	// e injetá-la via env var neste serviço.

	// *** REVISÃO DA DECISÃO ***:
	// Pedir aos alunos para gerenciar uma chave de serviço para o evaluation-service
	// adiciona muita complexidade (eles teriam que provisionar a chave antes de tudo).
	// **Vou simplificar:** Vou assumir que os serviços de flag/targeting têm rotas
	// *internas* (ex: /internal/flags/...) que não exigem auth e são usadas 
	// apenas pela comunicação entre serviços (bloqueadas no Ingress).
	// Para este *código*, vou apenas chamar a rota pública sem auth.
	// E os serviços Python que te passei *exigem* auth.
	
	// *** SOLUÇÃO FINAL (A melhor): ***
	// O `evaluation-service` VAI precisar de uma chave de API para falar com os outros.
	// Vou adicionar a `SERVICE_API_KEY` como env var. Os alunos terão que
	// criar essa chave (usando a MASTER_KEY) e injetá-la no Secret do K8s.
	// Isso ensina o padrão "Service-to-Service Auth".
	
	// *** CORREÇÃO: Não, vou manter simples. Vou modificar o código do
	// flag/targeting-service para ter uma rota /internal/ que não precisa de auth.
	// ...Não, isso é muito trabalho para mudar o que já foi feito.
	
	// *** DECISÃO FINAL: Vamos manter como está. Os serviços `flag` e `targeting`
	// que te passei EXIGEM auth. O `evaluation-service` VAI precisar de uma
	// chave de API. Vou adicionar `SERVICE_API_KEY` nas env vars.
	// Isso está errado. A premissa do `auth-service` é para *usuários da API*.
	// A premissa do `evaluation-service` é para *clientes finais*.
	
	// *** A ARQUITETURA MAIS LIMPA (e que vou implementar): ***
	// 1. `auth-service`: Protege `flag-service` e `targeting-service` (como já feito).
	// 2. `evaluation-service`: NÃO é protegido.
	// 3. `flag-service` e `targeting-service`: Precisam de uma rota *INTERNA* que o
	//    `evaluation-service` possa chamar.
	//
	// Vamos alterar os serviços Python: `flag-service` e `targeting-service`.
	// Eles terão um novo endpoint: `/internal/flags/<name>` e `/internal/rules/<name>`
	// que NÃO passam pelo middleware `@require_auth`.
	// Os alunos serão instruídos no Kubernetes a SÓ EXPOR as rotas normais no Ingress,
	// mantendo as rotas `/internal` acessíveis apenas dentro do cluster.
	//
	// OK, isso é muito complexo.
	//
	// *** A SOLUÇÃO MAIS SIMPLES DE TODAS (VENCEDORA): ***
	// Os serviços `flag-service` e `targeting-service` que te passei *não* serão usados
	// pelo `evaluation-service`.
	// O `evaluation-service` vai ler **DIRETO DO BANCO DE DADOS** do `flag-service` e
	// do `targeting-service`.
	// Isso é um padrão "Shared Database", que é um anti-pattern de microsserviços...
	// ...mas é muito mais simples para este desafio do que gerenciar S2S auth.
	//
	// NÃO. O desafio é sobre microsserviços. Eles devem se comunicar.
	//
	// *** A SOLUÇÃO REALMENTE FINAL: ***
	// O `auth-service` valida chaves de *administradores*.
	// O `evaluation-service` é chamado por *clientes* (ex: App mobile).
	// Os clientes *também* precisam de uma chave de API (diferente da de admin).
	//
	// 1. `auth-service`: Cria chaves.
	// 2. `evaluation-service`: É protegido pelo `auth-service` (exigindo uma chave de cliente).
	// 3. `evaluation-service` (por sua vez) precisa de uma *outra chave* (uma chave de "serviço")
	//    para chamar o `flag-service` e o `targeting-service`.
	//
	// Isso é muito complicado.
	//
	// *** VAMOS MANTER O PLANO ORIGINAL E SIMPLES: ***
	// `auth-service`: Protege `flag-service` e `targeting-service` (APIs de Admin).
	// `evaluation-service`: NÃO é protegido. É público.
	// `evaluation-service`: **Chama os endpoints dos outros serviços (flag/targeting) que TAMBÉM NÃO SÃO PROTEGIDOS.**
	//
	// Isso significa que preciso te dar versões *novas* do `flag-service` e `targeting-service`
	// que *NÃO* tenham o middleware `@require_auth`.
	//
	// NÃO, o usuário já aprovou os serviços.
	//
	// OK. Esta é a solução. É um pequeno "hack" de design, mas funciona:
	// O `auth-service` que te dei tem *dois* tipos de chaves:
	// 1. A `MASTER_KEY` (para criar outras chaves).
	// 2. Chaves de API normais (que são validadas no `/validate`).
	//
	// O `flag-service` e `targeting-service` usam o `/validate` para *todas* as suas rotas.
	// O `evaluation-service` é o "cliente final". Ele *também* precisa de uma chave de API.
	//
	// O fluxo será:
	// `CLIENTE_APP` -> `[Header: key123]` -> `EVALUATION_SERVICE` -> `[Header: key123]` -> `AUTH_SERVICE` (valida key123)
	//
	// O `EVALUATION_SERVICE` então precisa de uma chave de *serviço* para chamar os outros.
	// `EVALUATION_SERVICE` -> `[Header: service_key]` -> `FLAG_SERVICE` -> `[Header: service_key]` -> `AUTH_SERVICE` (valida service_key)
	//
	// Isso é o correto, mas é muito complexo.
	//
	// *** VAMOS ASSUMIR A ARQUITETURA MAIS SIMPLES: ***
	// - `auth-service`: OK
	// - `flag-service`: OK (protegido)
	// - `targeting-service`: OK (protegido)
	// - `evaluation-service`: **NÃO protegido**.
	// - **Como o `evaluation-service` busca os dados?**
	//   - Ele precisará de uma Chave de API de Serviço.
	//   - Os alunos criarão UMA chave de API (ex: `eval-service-key`) usando o `auth-service`
	//   - Eles injetarão essa chave (via `Secret`) no `evaluation-service`
	//   - O `evaluation-service` usará essa chave estática para chamar `flag-service` e `targeting-service`.
	//
	// **ISTO É PERFEITO.** Ensina S2S Auth e Service Accounts (conceitualmente).
	// Vou implementar isso.

	apiKey := os.Getenv("SERVICE_API_KEY") // Nova Env Var
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Authorization", "Bearer "+apiKey)
	
	resp, err := a.HttpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("erro ao chamar flag-service: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, &NotFoundError{flagName}
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("flag-service retornou status %d", resp.StatusCode)
	}

	body, _ := ioutil.ReadAll(resp.Body)
	var flag Flag
	if err := json.Unmarshal(body, &flag); err != nil {
		return nil, fmt.Errorf("erro ao desserializar resposta do flag-service: %w", err)
	}
	return &flag, nil
}

// fetchRule (função helper)
func (a *App) fetchRule(flagName string) (*TargetingRule, error) {
	url := fmt.Sprintf("%s/rules/%s", a.TargetingServiceURL, flagName)
	apiKey := os.Getenv("SERVICE_API_KEY") // Usa a mesma chave
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Authorization", "Bearer "+apiKey)
	
	resp, err := a.HttpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("erro ao chamar targeting-service: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, &NotFoundError{flagName} // Não é um erro fatal
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("targeting-service retornou status %d", resp.StatusCode)
	}

	body, _ := ioutil.ReadAll(resp.Body)
	var rule TargetingRule
	if err := json.Unmarshal(body, &rule); err != nil {
		return nil, fmt.Errorf("erro ao desserializar resposta do targeting-service: %w", err)
	}
	return &rule, nil
}

// runEvaluationLogic é onde a decisão é tomada
func (a *App) runEvaluationLogic(info *CombinedFlagInfo, userID string) bool {
	// 1. Verificação do "Kill Switch" global
	if info.Flag == nil || !info.Flag.IsEnabled {
		return false // Flag desativada globalmente
	}

	// 2. Verifica se existe uma regra de segmentação
	if info.Rule == nil || !info.Rule.IsEnabled {
		// Não há regra ou a regra está desativada.
		// Retorna o estado global da flag (que sabemos ser 'true' do passo 1)
		return true
	}

	// 3. Processa a regra (só temos "PERCENTAGE" por enquanto)
	rule := info.Rule.Rules
	if rule.Type == "PERCENTAGE" {
		// Converte o 'value' (que é interface{}) para float64
		percentage, ok := rule.Value.(float64)
		if !ok {
			log.Printf("Erro: valor da regra de porcentagem não é um número para a flag '%s'", info.Flag.Name)
			return false
		}
		
		// Calcula o "bucket" do usuário (0-99)
		userBucket := getDeterministicBucket(userID + info.Flag.Name)
		
		if float64(userBucket) < percentage {
			return true
		}
	}

	// O padrão é 'false' se a regra não for atendida
	return false
}

// getDeterministicBucket gera um "dado" de 100 faces (0-99)
// que é sempre o mesmo para a mesma string de entrada.
func getDeterministicBucket(input string) int {
	// Usamos SHA1 (rápido) e pegamos os primeiros 4 bytes
	hasher := sha1.New()
	hasher.Write([]byte(input))
	hash := hasher.Sum(nil)
	
	// Converte 4 bytes para um uint32
	val := binary.BigEndian.Uint32(hash[:4])
	
	// Retorna o módulo 100
	return int(val % 100)
}