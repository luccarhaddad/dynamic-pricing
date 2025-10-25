# Guia de Experimentos - Dynamic Pricing System

## 🎯 Visão Geral

Este sistema implementa experimentos **determinísticos e replicáveis** para análise de performance do sistema de pricing dinâmico.

## ✅ O que foi implementado

### 1. **Determinismo Completo**
- ✅ **Event Generator**: Usa seed configurável para gerar eventos idênticos
- ✅ **Flink Job**: Usa timestamp da janela (windowEnd) ao invés de System.currentTimeMillis()
- ✅ **Reproducibilidade**: Mesmo seed = mesmos resultados

### 2. **API de Experimentos**
- ✅ `/api/v1/experiment/status` - Status do experimento atual
- ✅ `/api/v1/experiment/metrics` - Métricas agregadas do experimento
- ✅ `/api/v1/experiment/zones` - Dados de todas as zonas

### 3. **Frontend Melhorado**
- ✅ Exibe status do experimento (deterministic, seed, scenario)
- ✅ Visualização em tempo real das mudanças de preço
- ✅ Suporte para 16 zonas

### 4. **Experimento Baseline**
- ✅ Apenas o experimento básico (sem falhas)
- ✅ Configuração simplificada
- ✅ Script automatizado

---

## 🚀 Como Rodar o Experimento

### Opção 1: Script Automatizado (Recomendado)

```bash
# Rodar experimento baseline completo
./run-experiment.sh
```

Isso irá:
1. Iniciar toda a infraestrutura (Kafka + PostgreSQL)
2. Rodar o experimento por 2 minutos
3. Coletar métricas a cada 5 segundos
4. Salvar resultados em `experiment-results/metrics-baseline.csv`
5. Gerar sumário em `experiment-results/experiment-summary.csv`

### Opção 2: Modo Manual

```bash
# 1. Iniciar sistema completo
./start-all.sh

# 2. Aguardar ~30 segundos para estabilizar

# 3. Acessar frontend e ver experimento em tempo real
# http://localhost:3000

# 4. Consultar status do experimento
curl http://localhost:8081/api/v1/experiment/status | jq

# 5. Ver métricas agregadas
curl http://localhost:8081/api/v1/experiment/metrics | jq

# 6. Parar o sistema
./stop-all.sh
```

---

## 📊 Endpoints Disponíveis

### Status do Experimento
```bash
curl http://localhost:8081/api/v1/experiment/status
```

Resposta:
```json
{
  "deterministic": "true",
  "seed": "12345",
  "scenario": "baseline",
  "failureRate": "0.0",
  "networkDelayMs": "0",
  "burstMultiplier": "1.0"
}
```

### Métricas do Experimento
```bash
curl http://localhost:8081/api/v1/experiment/metrics
```

Resposta:
```json
{
  "activeZones": 16,
  "totalSnapshots": 16,
  "averageSurge": 1.2,
  "minSurge": 1.0,
  "maxSurge": 2.5,
  "totalDemand": 150,
  "totalSupply": 240,
  "averageRatio": 0.625,
  "surgeDistribution": {
    "normal": 10,
    "low": 4,
    "medium": 1,
    "high": 1,
    "extreme": 0
  }
}
```

### Dados de Todas as Zonas
```bash
curl http://localhost:8081/api/v1/experiment/zones
```

---

## 🎨 Visualização no Frontend

Acesse: **http://localhost:3000**

O dashboard mostra:
- ✅ **Status do Experimento**: Modo determinístico, seed, cenário
- ✅ **16 Zonas**: Cards com surge multiplier, demanda e oferta
- ✅ **Atualização em Tempo Real**: Refresh a cada 2 segundos
- ✅ **Cores**: Verde (aumento), Vermelho (redução), Neutro (sem mudança)

---

## 🔬 Sobre Determinismo

### O que torna um experimento determinístico?

1. **Seed Fixo**: Todos os números aleatórios usam a mesma seed
2. **IDs Determinísticos**: Drivers e riders recebem IDs baseados em índice
3. **Timestamps da Janela**: Flink usa timestamp da janela ao invés de System.currentTimeMillis()
4. **Ordem Consistente**: Eventos são gerados na mesma ordem

### Como verificar determinismo?

```bash
# Rodar experimento 1
./run-experiment.sh
mv experiment-results/metrics-baseline.csv baseline-run1.csv

# Rodar experimento 2
./run-experiment.sh
mv experiment-results/metrics-baseline.csv baseline-run2.csv

# Comparar resultados
diff baseline-run1.csv baseline-run2.csv
# Não deve haver diferenças!
```

---

## 📈 Análise de Resultados

### Arquivos Gerados

```
experiment-results/
├── metrics-baseline.csv          # Métricas detalhadas por zona
└── experiment-summary.csv        # Sumário agregado
```

### Estrutura do CSV de Métricas

```csv
timestamp,zone_id,surge_multiplier,demand,supply,ratio
1234567890,1,1.5,15,10,1.5
1234567895,2,1.0,8,12,0.67
...
```

### Análise com Python

```python
import pandas as pd

# Carregar dados
df = pd.read_csv('experiment-results/metrics-baseline.csv')

# Estatísticas básicas
print(df.groupby('zone_id')['surge_multiplier'].describe())

# Visualizar série temporal
import matplotlib.pyplot as plt
plt.plot(df['timestamp'], df['surge_multiplier'])
plt.show()
```

---

## 🛠️ Configuração

### Variáveis de Ambiente

Edite `start-all.sh` ou exporte antes de rodar:

```bash
export DETERMINISTIC=true          # Modo determinístico
export EXPERIMENT_SEED=12345       # Seed do experimento
export SCENARIO=baseline          # Cenário atual
export FAILURE_RATE=0.0           # Taxa de falha (0.0-1.0)
export NETWORK_DELAY_MS=0         # Delay de rede artificial
export BURST_MULTIPLIER=1.0       # Multiplicador de burst
```

### Arquivo de Configuração

Edite `services/event-generator/src/main/resources/application.yml`:

```yaml
experiment:
  deterministic: true
  seed: 12345
  scenario: baseline
  failure-rate: 0.0
  network-delay-ms: 0
  burst-multiplier: 1.0
```

---

## 🐛 Troubleshooting

### Sistema não inicia
```bash
# Limpar e reiniciar
./stop-all.sh
cd infra && docker compose down -v && cd ..
./start-all.sh
```

### Frontend não mostra dados
```bash
# Verificar se API está respondendo
curl http://localhost:8081/api/v1/health

# Verificar logs
tail -f logs/pricing-api.log
```

### Experimento não reproduz os mesmos resultados
```bash
# Verificar se Flink foi recompilado após mudanças
./gradlew :flink-pricing-job:shadowJar

# Verificar seed no log
grep "seed" logs/event-generator.log
```

---

## 📚 Próximos Passos

Melhorias futuras que podem ser implementadas:

1. **Mais Cenários**: Network delay, dropped events, burst traffic
2. **Visualizações**: Gráficos de linha, histogramas
3. **Comparação**: Overlay de múltiplos experimentos
4. **Estatísticas**: ANOVA, correlações, testes de hipótese
5. **UI de Configuração**: Formulário para configurar experimentos via web

---

## ✅ Checklist de Experimentos

Antes de rodar um experimento:

- [ ] Variáveis de ambiente configuradas
- [ ] Seed definido e documentado
- [ ] Cenário documentado
- [ ] Infraestrutura limpa (sem dados antigos)
- [ ] Todos os serviços rodando
- [ ] Frontend acessível
- [ ] Métricas sendo coletadas

---

**🎉 Pronto para experimentação!**

Para dúvidas ou problemas, verifique os logs em `logs/` ou consulte o README.md principal.

