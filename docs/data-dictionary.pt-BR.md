# Dicionário de dados: Catálogo de produtos do e-commerce brasileiro

[Read in English](data-dictionary.md)

Regra geral: nenhum valor ruim é apagado. Quando um valor é corrigido, o original fica numa coluna `*_raw`, e o motivo fica numa coluna `*_flag`. A única exclusão são 224 linhas de SAC de marcas que pediram remoção.

Período: as ofertas foram coletadas em 2019 (14,7 mi), 2020 (92,6 mi) e 2024 (7,3 mi), por crawlers próprios e feeds de afiliados.

---

## plataformas.parquet (13 linhas)

| Coluna | Tipo | Descrição |
|---|---|---|
| id | int | Identificador da plataforma |
| name | texto | Nome: Moovin, xTech, NuvemShop, Vtex, EzCommerce/Lynx, CiaShop, Magento, Shopify, Awin/Zanox, Magazine Luiza / BazaarVoice, AdMatic, Mercado Shops, Jet Commerce |

Observação: "Awin/Zanox" e "Magazine Luiza / BazaarVoice" não são plataformas de loja. São a origem dos dados (rede de afiliados e API de reviews). Ficam como estão, explicadas aqui.

## lojas.parquet (17.899 linhas)

Lojas cadastradas no projeto. Só 7.179 têm ofertas no catálogo. As outras foram cadastradas e nunca coletadas, ou não retornaram produtos.

| Coluna | Tipo | Descrição |
|---|---|---|
| id | int | Identificador da loja (é o `store_id` das ofertas) |
| name | texto | Nome da loja, com texto embaralhado e códigos HTML reparados |
| name_flag | texto | `ok`; `reparado` (609: "Tubar&#227;o Center" → "Tubarão Center"); `caractere_perdido` (151: o "�" já estava gravado no banco desde a coleta e não dá para recuperar) |
| name_raw | texto | Nome como estava no banco |
| url | texto | Domínio da loja |
| slug | texto | Slug refeito a partir do nome, sem os bugs antigos (o `²` que apagava o `2` e o número final que incrementava) |
| slug_raw | texto | Slug antigo, usado nas URLs dos sites |
| active | bool | Loja ativa no projeto. Lojas foram inativadas por pedido de remoção (ex.: 7 lojas de uma vez em `reexporta_produtos.sql`), por site fora do ar ou "em manutenção", ou caso a caso |
| created_at | data/hora | Data de cadastro da loja no projeto |
| platform_id | int | Plataforma mais frequente nos feeds da loja (→ plataformas.id); vazio quando não há feed |

## caracteristicas.parquet (3.102 linhas)

Chaves da ficha técnica que receberam um título em forma de pergunta para os sites.

| Coluna | Tipo | Descrição |
|---|---|---|
| id | int | Identificador |
| key | texto | Chave como aparece na ficha ("Tipo de CD/DVD") |
| question | texto | Pergunta usada nas páginas ("Qual o tipo de CD/DVD?"), gerada por regra (`seta_titulos_caracteriscias_em_forma_de_pergunta.sql`) |

## grupos.parquet (18.328.454 linhas)

Grupos de produto: a mesma peça vendida em lojas diferentes, ligada pelo agrupamento em 2 saltos sobre 11 chaves de texto e código mais a assinatura da imagem (ver [metodologia](methodology.md)).

| Coluna | Tipo | Descrição |
|---|---|---|
| id | int | Identificador do grupo (é o `group_id` das ofertas) |
| short_name | texto | Nome mais curto entre as ofertas com imagem, preferindo as com preço. Calculado na criação ou reativação do grupo, e não recalculado quando ofertas saem |
| long_name | texto | Nome mais longo das ofertas (mesmo momento de cálculo) |
| created_at | data/hora | Criação do grupo |
| last_change | data/hora | Última vez que uma oferta do grupo recebeu preço novo ou mudou |
| last_change_is_bulk_date | bool | `true` quando `last_change` = 04/04/2022 00:03:14.763, data gravada em massa em ~437 mil grupos (não é a data real) |
| active | bool | O grupo tem pelo menos uma oferta com imagem baixada. Não considera preço |
| offers | int | Número de ofertas no grupo |
| stores | int | Número de lojas diferentes |
| brands | int | Número de marcas diferentes (texto da marca normalizado) |
| group_flag | texto | `ok`; `grande_demais` (3.107 grupos com mais de 1.000 ofertas: encadeamento do reagrupamento); `muitas_marcas` (11.743 com mais de 10 marcas); `sem_ofertas` (14.999) |

## produtos/ (114.640.012 linhas)

Uma linha por oferta coletada (produto numa loja).

| Coluna | Tipo | Descrição |
|---|---|---|
| id | int | Identificador da oferta. Há um salto de +39.517.486 nos ids na migração de dez/2019 |
| store_id | int | Loja (→ lojas.id) |
| collected_at | data/hora | Primeira coleta da oferta |
| name | texto | Nome do produto, com texto embaralhado reparado. Já vinha normalizado na origem (maiúsculas, espaços) |
| name_flag | texto | `ok`; `reparado` (519.564); `caractere_perdido` (978) |
| name_raw | texto | Nome como estava no banco |
| url | texto | URL da oferta na loja, no momento da coleta |
| brand | texto | Marca informada pela loja ou pelo feed. Foi normalizada na origem: marcas só com símbolos apagadas, longas cortadas em 30 caracteres |
| availability_raw | texto | Disponibilidade como veio (13 grafias) |
| availability | texto | `disponivel`, `indisponivel` ou vazio (85% das ofertas) |
| availability_reliable | bool | `false` nas lojas 1, 2 e 3 (Submarino, Americanas, Shoptime), onde um dos caminhos de coleta gravava "esgotado" como "em estoque". O problema foi confirmado no código do crawler da B2W; nas outras lojas não foi verificado, então o campo deve ser lido com cautela em qualquer loja |
| price_raw | decimal | Preço como estava no banco |
| price | decimal | Preço em reais; vazio quando `price_flag` ≠ `ok`. Preço de promoção quando havia, senão o preço normal. Em parte das ofertas de Americanas e Shoptime foi gravado o preço do Submarino |
| price_flag | texto | `ok`; `zero` (28,1 mi); `inativo_99999` (1,5 mi: o crawler gravava 99.999,99 para produto inativo) |
| group_id | int | Grupo do produto (→ grupos.id). Vazio em 7,4 mi ofertas, em parte porque a carga das imagens baixadas zerava o grupo |
| group_rule | texto | Regra que pôs a oferta no grupo atual (após o reagrupamento): `EAN longo`, `productName`, `productName_fingerprint`, `productName_metaphone`, `productName_ngram`, `productName_tokenizada_fingerprint`, `productUrl`, `productImage_hash_Imagio_ComputeHash`, `EAN curto + Brand` (e variações) |
| group_rule_original | texto | Regra do primeiro agrupamento, o mais conservador. Vazia quando um script de desagrupamento apagou o valor |
| image_hash | texto | Assinatura da imagem: a foto reduzida a 16×16 em tons de cinza e passada por SHA-256. A mesma imagem (mesmos pixels depois da redução) tem a mesma assinatura; como o hash é exato, uma foto redimensionada ou recomprimida pela loja costuma ter assinatura diferente. Formato: os 32 bytes escritos em decimal e colados (80–84 caracteres), como estava no banco. Mantido assim: não há conversão segura para hexadecimal, e para comparar imagens funciona do mesmo jeito. Para calcular o hash de imagens novas, veja a [SimilarImageFinder](https://github.com/CaiqueDourado/SimilarImageFinder); ela usa os pixels decodificados, então não reproduz estes valores |
| image_width / image_height | int | Dimensões da imagem **depois** de otimizada. Podem vir de outra imagem por uma falha de concorrência no download. Usar com cuidado |
| image_is_generic | bool | `true` quando a mesma assinatura aparece em mais de 100 produtos (imagem "sem foto", logo da loja). Essas imagens não contam no agrupamento |

## ficha/ (31.904.957 linhas)

Ficha técnica: uma linha por chave/valor de um produto.

| Coluna | Tipo | Descrição |
|---|---|---|
| id | int | Identificador da linha |
| product_id | int | Oferta (→ produtos.id) |
| position | int | Ordem da característica na página do produto |
| key | texto | Nome da característica (4.370 chaves diferentes; algumas tiveram a grafia normalizada na origem) |
| value | texto | Valor; vazio quando era `''`, `Null`, `-` etc. |
| value_raw | texto | Valor como estava no banco |

## eans/ (32.119.395 linhas)

Códigos de identificação do produto: uma linha por código.

| Coluna | Tipo | Descrição |
|---|---|---|
| id | int | Linha de origem no banco (repete quando o valor tinha vários códigos separados por vírgula) |
| product_id | int | Oferta (→ produtos.id) |
| code_index | int | Posição do código dentro do valor original (1, 2…) |
| code | texto | Código, sem espaços |
| value_raw | texto | Valor como estava no banco |
| ignored_in_grouping | bool | Código posto na lista negra do agrupamento: genérico (repetido em mais de 5 produtos da mesma loja), só letras, truncado, mais de 15 nomes diferentes, começa com 000, "SEM GTIN". Vazio em 10,4 mi linhas mais novas |
| code_type | texto | `gtin_valido` (79%, dígito verificador conferido); `gtin_digito_errado`; `numero_curto`; `numero_outro_tamanho` (inclui códigos NCM de 8 dígitos); `codigo_alfanumerico` (SKU da loja); `notacao_cientifica` (estragado pelo Excel, ex. `90E+12`); `texto`; `vazio` |
| source_key | texto | Chave da ficha que tem o mesmo código para o mesmo produto ("Código de Barras", "Isbn"…). A coluna original de origem nunca foi preenchida pelo crawler, por isso a origem vem da ficha |

## categorias/ (220.060.122 linhas)

Pedaços do caminho de categorias (breadcrumb) de cada oferta.

| Coluna | Tipo | Descrição |
|---|---|---|
| id | int | Identificador da linha |
| product_id | int | Oferta (→ produtos.id) |
| level | int | Posição do pedaço depois de quebrar o texto em `>`, `\|`, ` - `, `,` e `/`. Não é a profundidade da taxonomia da loja |
| category | texto | Texto da categoria. Nas linhas limpas em 2020, já vem com acentos, maiúsculas e plural padronizados (ex.: "Automotivos", "Femininos"); nas outras, como a loja escreveu |
| category_normalized | texto | Categoria unificada por chaves fonéticas e de fingerprint (normalização "hard" de 2020); vazia nas coletas posteriores |
| category_origin | texto | `limpa_2020` (86%) ou `original` |
| category_flag | texto | `ok`; `nivel_alto` (nível acima de 10: listas de tags de SEO de lojas VTEX); `codigo_ou_ruido` (códigos internos como `Coll-…`, `SkuOriginal-…`, só números, "No Magalu"); `curta_demais` |

Perdas conhecidas na origem estão em [data-quality.md](data-quality.md): toda categoria com número foi apagada em 2020 (ex.: "Galaxy J5"), e a terceira categoria dos feeds nunca foi gravada.
