# legacy/

[English](#english) · [Português](#português)

## English

[`agrupa_insere_grupos_produtos_similares.sql`](agrupa_insere_grupos_produtos_similares.sql) is the
SQL Server routine that grouped the catalog's offers into products (2020–2022), as it ran. It is here so
the [methodology](../docs/methodology.md) can be checked against the code. It is **read-only**: it depends on
the original database (tables, functions such as `nlp.dbo.converteArrayParaTabela` and `nlp.dbo.Slugify`,
and keys computed outside SQL) and is not meant to be run.

Only two things were changed: a header comment, and local file paths in comments, reduced to file names.

**What it does.** It loads ungrouped offers into a flat working table (l. 70–260). Then a cursor takes one offer
at a time (l. 460). For each offer it:

1. collects every offer that shares one of twelve keys with it (hop 1): long EAN, exact name, name fingerprint,
   metaphone, n-grams, token fingerprint, URL, short EAN + brand in four variants, and the image signature;
2. removes long-EAN matches whose names share no word, and logs them in `temp_agrupamentos_ignorados` (l. 1120–1165);
3. collects the offers that share a key with those (hop 2), with the same check (l. 1740–1780);
4. puts all of them in the lowest existing group id (l. 1815), or creates a group with a name, a slug and a status (l. 1840–1935);
5. writes the group, the rule and the value on each offer that had no group (l. 2085–2100).

**Known issues.** All of these are reflected in the published data and described in
[data-quality.md](../docs/data-quality.md):

- The name fingerprint was computed outside SQL by a function that **kept every other word**, so different products could share it.
- The shared-word check runs only for long-EAN matches (`tipo = 'EAN longo'`, l. 1152 and 1772). Image, short-code and n-gram matches are never checked, and nothing compares sizes, voltages or colours.
- With several rules linking the same offer, `UPDATE ... FROM` writes an arbitrary one as `group_rule` (l. 2087–2093). The deterministic `CROSS APPLY ... TOP 1` version is commented out.
- Offers that already have a group are never moved, and the result depends on the order in which offers arrive.
- Names are only computed when a group is created or reactivated (l. 1936–1945). An active group keeps its name even when its offers change.
- `active` counts offers with an image signature (l. 1902). The comment says "positive price and image", but price is not checked at creation.
- The slug loop increments the number after the last `-` when the slug already exists. A product whose name ends in a number (`tune-510`) can get the slug of the next model (`tune-511`).
- The EAN blacklist (more than 5 offers in one store, placeholders, codes without digits...) is a commented block (l. 284–341), run by hand.

**Today.** The matching logic was rewritten as a tested library, in Python and .NET:
**[DedupKit](https://github.com/CaiqueDourado/DedupKit)**. It fixes the fingerprint, checks shared words on every barcode match,
refuses pairs with different sizes, voltages or colours, does not depend on input order, and records every link and refusal.
Measured on synthetic data with known answers, it goes from 23% to 82–90% pairwise precision with about the same recall.
`DedupKit` keeps the old behaviour available (`LEGACY_RULES`, `mode="two_hop"`) to measure the difference.

## Português

[`agrupa_insere_grupos_produtos_similares.sql`](agrupa_insere_grupos_produtos_similares.sql) é a rotina em
SQL Server que agrupava as ofertas do catálogo em produtos (2020–2022), do jeito que rodava. Está aqui para que a
[metodologia](../docs/methodology.md) possa ser conferida com o código. É **só para leitura**: depende do banco original
(tabelas, funções como `nlp.dbo.converteArrayParaTabela` e `nlp.dbo.Slugify`, e chaves calculadas fora do SQL) e não é para ser executada.

Só duas coisas mudaram: um comentário de cabeçalho, e caminhos de arquivos locais em comentários, reduzidos ao nome do arquivo.

**O que faz.** Carrega as ofertas sem grupo numa tabela de trabalho plana (l. 70–260). Depois, um cursor pega uma oferta
por vez (l. 460). Para cada oferta:

1. junta toda oferta que divide com ela uma de doze chaves (salto 1): EAN longo, nome exato, fingerprint do nome,
   metaphone, n-gramas, fingerprint dos tokens, URL, EAN curto + marca em quatro variações e a assinatura da imagem;
2. tira os casamentos por EAN longo cujos nomes não têm nenhuma palavra em comum, e registra em `temp_agrupamentos_ignorados` (l. 1120–1165);
3. junta as ofertas que dividem uma chave com essas (salto 2), com a mesma conferência (l. 1740–1780);
4. coloca todas no menor id de grupo já existente (l. 1815), ou cria um grupo com nome, slug e status (l. 1840–1935);
5. grava o grupo, a regra e o valor em cada oferta que estava sem grupo (l. 2085–2100).

**Problemas conhecidos.** Todos aparecem nos dados publicados e estão descritos em
[data-quality.md](../docs/data-quality.md):

- O fingerprint do nome era calculado fora do SQL por uma função que **mantinha uma palavra sim, outra não**, então produtos diferentes podiam ter o mesmo.
- A conferência de palavra em comum só roda nos casamentos por EAN longo (`tipo = 'EAN longo'`, l. 1152 e 1772). Casamentos por imagem, código curto e n-gramas nunca são conferidos, e nada compara tamanho, voltagem ou cor.
- Quando várias regras ligam a mesma oferta, o `UPDATE ... FROM` grava uma qualquer como `group_rule` (l. 2087–2093). A versão determinística com `CROSS APPLY ... TOP 1` está comentada.
- Ofertas que já têm grupo nunca são movidas, e o resultado depende da ordem em que as ofertas chegam.
- Os nomes só são calculados quando o grupo é criado ou reativado (l. 1936–1945). Um grupo ativo mantém o nome mesmo quando as ofertas mudam.
- `active` conta ofertas com assinatura de imagem (l. 1902). O comentário fala em "preço positivo e imagem", mas o preço não é conferido na criação.
- O laço do slug incrementa o número depois do último `-` quando o slug já existe. Um produto cujo nome termina em número (`tune-510`) pode ganhar o slug do modelo seguinte (`tune-511`).
- A lista de EANs ignorados (mais de 5 ofertas numa só loja, valores de enchimento, códigos sem dígito...) é um bloco comentado (l. 284–341), rodado à mão.

**Hoje.** A lógica de agrupamento foi reescrita como biblioteca testada, em Python e .NET:
**[DedupKit](https://github.com/CaiqueDourado/DedupKit)**. Ela corrige o fingerprint, confere palavras em todo casamento por código,
recusa pares com tamanho, voltagem ou cor diferentes, não depende da ordem de entrada e registra cada ligação e cada recusa.
Medido em dados sintéticos com resposta conhecida, vai de 23% para 82–90% de precisão por pares, com cobertura quase igual.
O `DedupKit` mantém o comportamento antigo disponível (`LEGACY_RULES`, `mode="two_hop"`) para medir a diferença.
