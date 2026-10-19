# Catálogo de produtos do e-commerce brasileiro

[![validate](https://github.com/CaiqueDourado/catalogo-produtos-ecommerce-brasil/actions/workflows/validate.yml/badge.svg)](https://github.com/CaiqueDourado/catalogo-produtos-ecommerce-brasil/actions/workflows/validate.yml)
[![Dados: CC BY 4.0](https://img.shields.io/badge/dados-CC%20BY%204.0-lightgrey.svg)](LICENSE-DATA.md)
[![Código: MIT](https://img.shields.io/badge/código-MIT-blue.svg)](LICENSE)
[![Kaggle](https://img.shields.io/badge/Kaggle-base%20completa-20BEFF.svg)](https://www.kaggle.com/datasets/caiquedourado/catalogo-produtos-ecommerce-brasil)

[Read in English](README.md)

**114,6 milhões de ofertas de 7.179 lojas brasileiras, coletadas entre 2019 e 2024**, com ficha técnica, códigos de barras, categorias e **18,3 milhões de grupos de produto**: a mesma peça vendida em lojas diferentes, ligada por um agrupamento em 11 regras.

Este repositório tem uma amostra coerente (grupos inteiros, com todas as ofertas, fichas, códigos e categorias) e os scripts que geram a base. **A base completa (9,5 GB em Parquet) está no [Kaggle](https://www.kaggle.com/datasets/caiquedourado/catalogo-produtos-ecommerce-brasil).**

| Tabela | Linhas | O que é |
|---|---|---|
| `produtos` | 114.640.012 | Uma oferta: produto numa loja, com nome, marca, preço, disponibilidade, grupo e assinatura da imagem |
| `grupos` | 18.328.454 | Grupos de produto, com número de ofertas, lojas e marcas |
| `ficha` | 31.904.957 | Ficha técnica, uma linha por chave/valor (4.370 chaves) |
| `eans` | 32.119.395 | Códigos de identificação, classificados (79% GTIN com dígito verificador válido) |
| `categorias` | 220.060.122 | Caminhos de categoria das lojas, com normalização |
| `lojas` | 17.899 | Lojas, com plataforma de e-commerce |
| `caracteristicas` | 3.102 | Chaves da ficha com o título em forma de pergunta usado nos sites |
| `plataformas` | 13 | VTEX, Shopify, NuvemShop, Magento… |

As maiores lojas: Magazine Luiza (19,7 mi ofertas), Americanas (14,3 mi), Shoptime (11,2 mi), Submarino (10,7 mi), Extra (10,3 mi), Casas Bahia (9,9 mi), Amazon (7,3 mi), Dafiti (5,9 mi), Pontofrio (4,4 mi) e Kanui (1,8 mi). As 10 maiores somam 83% das ofertas.

## De onde vieram

O catálogo foi a base de uma rede de sites que eu construí entre 2019 e 2024: comparação de preços, fichas técnicas, guias de tamanho, SAC das marcas e "tudo sobre" cada produto. Entre eles:

- [Tudo Sobre Produtos](https://web.archive.org/web/20251021032358/https://tudosobreprodutos.com.br/tudo-sobre-bebedouro-cadence-pure-vita-elegant-0v)
- [Preço Atualizado](https://web.archive.org/web/2020/https://precoatualizado.com.br/)
- [Tamanhos](https://web.archive.org/web/20241107071917/https://tamanhos.com.br/tamanhos-medidas-dimensoes-voltimetro-digital-com-remote-0-a-0v-bateria-som-carro-azul-asx)
- [Atendimento ao Consumidor](https://web.archive.org/web/20201101002617/https://atendimentoaoconsumidor.com.br/assistencia-tecnica-garantia-energetico-monster-energy-47ml)
- [Busca Produto](https://web.archive.org/web/2020/https://buscaproduto.com.br/)

Cada página de produto desses sites era montada a partir de um grupo desta base.

A coleta usou três fontes:

- crawlers próprios das páginas das lojas (ficha técnica, códigos de barras, breadcrumbs);
- feeds de produtos (Google Shopping, Awin, VTEX, Shopify, NuvemShop…);
- descoberta de lojas pela plataforma de cada uma.

Tudo era gravado num data lake em SQL Server e exportado para cá com os scripts de `scripts/`.

## O agrupamento: a mesma peça em lojas diferentes

O coração da base é a coluna `group_id`. Cada oferta nova era comparada com as existentes por **11 chaves**, nesta ordem:

1. EAN longo (com uma lista negra de códigos genéricos e uma conferência de palavras do nome, para não juntar uma guitarra e um reservatório de carro que a loja cadastrou com o mesmo EAN);
2. nome exato;
3. fingerprint do nome;
4. metaphone;
5. n-gramas;
6. fingerprint dos tokens;
7. URL;
8. EAN curto + marca (4 variações);
9. **assinatura da imagem**.

Depois, um **reagrupamento em dois saltos** buscava produtos semelhantes aos do grupo. `group_rule_original` guarda a regra do primeiro agrupamento, o mais conservador. `group_rule` guarda a regra depois do reagrupamento, que junta mais e às vezes encadeia demais. Os 3.107 grupos com mais de 1.000 ofertas e os 11.743 com mais de 10 marcas estão marcados em `group_flag`. Use `group_rule_original` quando precisar de precisão.

### A assinatura da imagem

Cada foto de produto foi baixada, reduzida a 16×16 pixels em tons de cinza e passada por SHA-256 (`image_hash`). A técnica é simples, barata e funcionou bem em duas frentes:

- **Achar a mesma foto em tamanhos diferentes:** lojas que revendem o mesmo produto costumam usar a foto do fabricante, cada uma num tamanho e numa compressão. Reduzida a 16×16 em cinza, a foto vira a mesma assinatura. Isso ligou produtos que não tinham EAN e tinham nomes diferentes.
- **Descobrir imagens genéricas sem olhar uma por uma:** quando a mesma assinatura aparecia em mais de 100 produtos, era quase sempre um "sem foto" ou o logo da loja. Essas imagens viraram `image_is_generic` e deixaram de agrupar produtos.

## O que esses dados respondem

- Quais produtos aparecem em mais lojas, e quanto o preço varia entre elas no mesmo momento da coleta.
- Quais plataformas de e-commerce as lojas brasileiras usavam, e que tamanho de catálogo cada uma tinha.
- Como as lojas descrevem o mesmo produto: chaves de ficha técnica, sinônimos de atributos, categorias.
- A qualidade real dos códigos de barras no varejo brasileiro: GTIN válido, dígito errado, SKU no lugar de EAN, código estragado pelo Excel.
- Material de treino e teste para casamento de produtos (entity resolution) em português.

## Começando

```python
import duckdb
con = duckdb.connect()
con.sql("""
    SELECT g.short_name, p.store_id, p.price
    FROM 'produtos/*.parquet' p JOIN 'grupos.parquet' g ON g.id = p.group_id
    WHERE g.stores >= 5 AND p.price IS NOT NULL
    LIMIT 20
""")
```

A amostra deste repositório está em `sample/` (CSV, ~18 MB). Os arquivos têm os mesmos nomes e colunas da base completa.

## Documentação

- [Dicionário de dados](docs/data-dictionary.pt-BR.md): todas as colunas e seus valores
- [Metodologia](docs/methodology.md): coleta, agrupamento, normalização e build
- [Qualidade dos dados](docs/data-quality.md): o que foi corrigido, o que foi só marcado e o que se perdeu na origem

Regra da base: **marcar, não apagar**. Todo valor corrigido mantém o original numa coluna `*_raw`, e o motivo numa coluna `*_flag`.

## O que eu faria diferente

- **Guardar o dado bruto antes de normalizar.** Nome, marca e categoria foram normalizados no próprio lugar em 2020, e o texto original da loja se perdeu. Uma regra de plural transformou "Home" em "Homes".
- **Testar as funções de texto com casos em português.** O fingerprint que eu usava descartava uma palavra sim, uma não. Uma rotina de categorias apagou toda categoria com número, como "Galaxy J5".
- **Separar ingestão de enriquecimento.** A carga das imagens baixadas zerava o grupo do produto, e por isso parte das 7,4 milhões de ofertas está sem grupo.

## Licença e uso

- **Dados:** CC BY 4.0 ([LICENSE-DATA.md](LICENSE-DATA.md)).
- **Código:** MIT.
- **Conteúdo das lojas:** nomes, marcas e fichas técnicas são informação factual coletada das lojas e de feeds públicos de afiliados. As imagens não são distribuídas, só a assinatura de cada uma.
- **Pedidos de remoção:** os contatos de SAC das marcas que pediram remoção foram retirados (224 linhas).

## Como citar

Veja [CITATION.cff](CITATION.cff).
