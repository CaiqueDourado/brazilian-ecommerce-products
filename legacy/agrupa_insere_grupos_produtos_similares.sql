/*
=====================================================================================
 Original production routine of the 2020-2022 catalog (SQL Server), kept for reference.
 Read only: it depends on the original database and is not meant to be run.

 What it does: for each listing not yet grouped, collect the listings that share one of
 12 keys (hop 1), then the listings that share a key with those (hop 2); all join the
 lowest existing ProductGroup id, or a new group is created. Long-EAN matches whose names
 share no word are refused and logged in temp_agrupamentos_ignorados.

 Known issues (see README.md in this folder and ../docs/data-quality.md):
 - productName_fingerprint was computed outside SQL by a keyer that kept every other word;
 - the shared-word check runs only for long-EAN matches; sizes and voltages are never compared;
 - with several matching rules, UPDATE ... FROM records an arbitrary one as the rule;
 - names are only recalculated for new or reactivated groups; "active" only checks for an image;
 - the cursor processes one seed at a time, so the result depends on input order.

 Rewritten, tested and measured as a library: https://github.com/CaiqueDourado/DedupKit
 Local file paths in comments were reduced to file names. Code otherwise unchanged.
=====================================================================================
*/

USE nlp;

SET NOCOUNT ON

DECLARE
	@debug BIT = 0,
	@debugHard BIT = 0

/*

0: UPDATE Normaliza acentos
0: UPDATE Normaliza Brands
0: INSERT Insere EAN's com base nas características do produto

0: Limpa tentativas de agrupamento
1: Roda tentativa de agrupamento
2º Pega dados do produto atual
3º Pega produtos relacionados, e seus dados individuais
4º Pega todos os produtos relacionados aos dados individuais coletados
5º Seta counters: "_quantidade", "_lastProductGroupAdded" e "creationDAte"

-- Grupos que ficaram sem filhos, para remover
DELETE FROM nlp_data_lake.dbo.ProductGroup
WHERE 
	active = 1
	AND NOT EXISTS (
	
		SELECT TOP 1 1 FROM nlp_data_lake.dbo.CrawlerNewProductDetail
		WHERe
			productGroupId = nlp_data_lake.dbo.ProductGroup.id

	)

*/


		-- IMPORTANTE! Antes de agrupar, normalizar BRAND's
		-- seta_brands_normalizada_pai.sql



-- drop table #eansParaIgnorar
-- drop table #eansParaIgnorar2





WHILE 1 = 1
BEGIN


	-- Insere dados na tabela Flat
	-- IF (SELECT COUNT(*) FROM [nlp_data_lake].dbo.[temp_flat-table_product_detail]) = 0 
	INSERT [nlp_data_lake].dbo.[temp_flat-table_product_detail] (id, productName, productUrl, productGroupId, productName_fingerprint, productName_metaphone, productName_ngram, productName_tokenizada, productName_tokenizada_fingerprint,feed_brand, feed_brand_tokenizada, feed_brand_ngram, feed_brand_fingerprint, productImage_hash_Imagio_ComputeHash, productImage_sem_imagem_desconsiderar, productPrice, productRodouRotinaGroup, ean_longo, ean_curto, ean_curto_feed_brand,ean_curto_feed_brand_ngram,ean_curto_feed_brand_fingerprint,ean_curto_feed_brand_tokenizada)
	select 
		 * ,
		CASE WHEN ean_curto <> '' AND feed_brand <> '' THEN ean_curto + '/' + feed_brand ELSE '' END as ean_curto_feed_brand,
		CASE WHEN ean_curto <> '' AND feed_brand_ngram <> '' THEN ean_curto + '/' + feed_brand_ngram ELSE '' END as ean_curto_feed_brand_ngram,
		CASE WHEN ean_curto <> '' AND feed_brand_fingerprint <> '' THEN ean_curto + '/' + feed_brand_fingerprint ELSE '' END as ean_curto_feed_brand_fingerprint,
		CASE WHEN ean_curto <> '' AND feed_brand_tokenizada <> '' THEN ean_curto + '/' + feed_brand_tokenizada ELSE '' END as ean_curto_feed_brand_tokenizada
	
	from (

		select  top 2000000
			p.id,
			p.productName,
			p.productUrl,
			p.productGroupId,
			CASE WHEN p.productName_fingerprint like '% % %' THEN p.productName_fingerprint /* Com 2 espaços em branco no meio  */ ELSE '' END as productName_fingerprint,
			CASE WHEN LEN(p.productName_metaphone) > 3 AND REPLACE(p.productName, '*', '|') like '% %' ESCAPE '|' /* Com mais de 3 caracteres no metaphone, e pelo menos 1 espaço no nome */ THEN p.productName_metaphone ELSE '' END as productName_metaphone,
			p.productName_ngram,
			p.productName_tokenizada,
			CASE WHEN p.productName_tokenizada_fingerprint like '% %' THEN p.productName_tokenizada_fingerprint /* Com 1 espaço em branco no meio  */ ELSE '' END as productName_tokenizada_fingerprint,
			CASE WHEN p.feed_brand not in ('brand','importado','Produto Importado','Original', '-','Não Informado','Indisponível','N/a','N/D') THEN p.feed_brand ELSE '' END as feed_brand,
			CASE WHEN p.feed_brand_tokenizada not in ('brand','import','produt import','original', 'nao inform', 'indispon') THEN p.feed_brand_tokenizada ELSE '' END as feed_brand_tokenizada,
			CASE WHEN p.feed_brand_ngram not in ('iaddoduimmpo odorpoprrorttatout','anbrndra','addoimmporportta','algiiginnaorri''iadaodofoinmananfo orrm', 'dielinisivndnionpospve', 'an', 'dn') THEN p.feed_brand_ngram ELSE '' END as feed_brand_ngram,
			CASE WHEN p.feed_brand_fingerprint like '% % %' THEN p.feed_brand_fingerprint /* Com 2 espaços em branco no meio  */ ELSE '' END as feed_brand_fingerprint,
			p.productImage_hash_Imagio_ComputeHash,
			p.productImage_sem_imagem_desconsiderar,
			(
				select top 1 pr.productPrice from [nlp_data_lake].[dbo].CrawlerNewProduct pr with (nolock)  
				where
					pr.productUrl = p.CrawlerNewProductProductUrl 
					and pr.sourceId = p.sourceId
					and pr.productPrice > 0

			) as productPrice,
			p.productRodouRotinaGroup,

				CASE WHEN (

				(
					len(valor) >= 5 -- EANS com mais de 4 dígitos
					and valor LIKE '%[^0-9]%' -- EANS que contén letras
				)
				OR		
				(
					len(valor) >= 7 -- EANS com mais de 7 dígitos
					and valor NOT LIKE '%[^0-9]%' -- EANS que contén números

					AND (
						len(convert(varchar, TRY_CONVERT(bigint,  valor))) >= 6 -- 6 ou mais dígitos numéricos '000000123456'
						OR
						len(convert(varchar, TRY_CONVERT(bigint,  valor))) IS NULL -- Falha ao converter para Big INT '12856510658165165156'
					) 
				)
			)
			AND desconsiderar_nos_agrupamentos = 0 THEN valor ELSE '' END as ean_longo,

			CASE WHEN 
			(

					/* ------------------------------- Eans curtos ------------------------------- */

					(
						len(valor) BETWEEN 3 AND 4 -- EANS de 3 a 4 dígitos
						and valor LIKE '%[^0-9]%' -- EANS que contén letras
					)
					OR
					(
						len(valor) BETWEEN 4 AND 6 -- EANS de 3 a 6 dígitos
						and valor NOT LIKE '%[^0-9]%' -- EANS que contén números
					)	
					OR
					(
						len(valor) >= 7 -- EANS com mais de 7 dígitos
						AND valor NOT LIKE '%[^0-9]%' -- EANS que contén números
						AND len(convert(varchar, TRY_CONVERT(bigint,  valor))) <= 5 -- 5 ou menos dígitos numéricos '1000000012345'
					)

					/* ------------------------------- Eans curtos ------------------------------- */
				) AND desconsiderar_nos_agrupamentos = 0 THEN valor ELSE '' END as ean_curto


		from nlp_data_lake.dbo.CrawlerNewProductDetail p with (nolock) 
		left join nlp_data_lake.dbo.CrawlerNewProductDetailEAN e with (nolock) on e.idCrawlerNewProductDetail = p.id
		inner join nlp_management.dbo.Source s with (nolock) on s.id = p.sourceId
		LEFT JOIN  [nlp_data_lake].dbo.[temp_flat-table_product_detail] t on t.id = p.id
		where		
			s.active = 1
			AND t.id IS NULL
	
	) as tb


   IF @@ROWCOUNT < 2000000 BREAK;

END






---- Insere os que ficaram pendentes
--select 
--	 tb.* ,
--	CASE WHEN tb.ean_curto <> '' AND tb.feed_brand <> '' THEN tb.ean_curto + '/' + tb.feed_brand ELSE '' END as ean_curto_feed_brand,
--	CASE WHEN tb.ean_curto <> '' AND tb.feed_brand_ngram <> '' THEN tb.ean_curto + '/' + tb.feed_brand_ngram ELSE '' END as ean_curto_feed_brand_ngram,
--	CASE WHEN tb.ean_curto <> '' AND tb.feed_brand_fingerprint <> '' THEN tb.ean_curto + '/' + tb.feed_brand_fingerprint ELSE '' END as ean_curto_feed_brand_fingerprint,
--	CASE WHEN tb.ean_curto <> '' AND tb.feed_brand_tokenizada <> '' THEN tb.ean_curto + '/' + tb.feed_brand_tokenizada ELSE '' END as ean_curto_feed_brand_tokenizada

--into #pendenteInserir2	
--from (

--	select   
--		p.id,
--		p.productName,
--		p.productUrl,
--		p.productGroupId,
--		CASE WHEN p.productName_fingerprint like '% % %' THEN p.productName_fingerprint /* Com 2 espaços em branco no meio  */ ELSE '' END as productName_fingerprint,
--		CASE WHEN LEN(p.productName_metaphone) > 3 AND p.REPLACE(productName, '*', '|') like '% %' ESCAPE '|' /* Com mais de 3 caracteres no metaphone, e pelo menos 1 espaço no nome */ THEN p.productName_metaphone ELSE '' END as productName_metaphone,
--		p.productName_ngram,
--		p.productName_tokenizada,
--		CASE WHEN p.productName_tokenizada_fingerprint like '% %' THEN p.productName_tokenizada_fingerprint /* Com 1 espaço em branco no meio  */ ELSE '' END as productName_tokenizada_fingerprint,
--		CASE WHEN p.feed_brand not in ('brand','importado','Produto Importado','Original', '-','Não Informado','Indisponível','N/a','N/D') THEN p.feed_brand ELSE '' END as feed_brand,
--		CASE WHEN p.feed_brand_tokenizada not in ('brand','import','produt import','original', 'nao inform', 'indispon') THEN p.feed_brand_tokenizada ELSE '' END as feed_brand_tokenizada,
--		CASE WHEN p.feed_brand_ngram not in ('iaddoduimmpo odorpoprrorttatout','anbrndra','addoimmporportta','algiiginnaorri''iadaodofoinmananfo orrm', 'dielinisivndnionpospve', 'an', 'dn') THEN p.feed_brand_ngram ELSE '' END as feed_brand_ngram,
--		CASE WHEN p.feed_brand_fingerprint like '% % %' THEN p.feed_brand_fingerprint /* Com 2 espaços em branco no meio  */ ELSE '' END as feed_brand_fingerprint,
--		p.productImage_hash_Imagio_ComputeHash,
--		p.productImage_sem_imagem_desconsiderar,
--		(
--			select top 1 pr.productPrice from [nlp_data_lake].[dbo].CrawlerNewProduct pr with (nolock)  
--			where
--				pr.productUrl = p.CrawlerNewProductProductUrl 
--				and pr.sourceId = p.sourceId
--				and pr.productPrice > 0

--		) as productPrice,
--		p.productRodouRotinaGroup,

--			CASE WHEN (

--			(
--				len(valor) >= 5 -- EANS com mais de 4 dígitos
--				and valor LIKE '%[^0-9]%' -- EANS que contén letras
--			)
--			OR		
--			(
--				len(valor) >= 7 -- EANS com mais de 7 dígitos
--				and valor NOT LIKE '%[^0-9]%' -- EANS que contén números

--				AND (
--					len(convert(varchar, TRY_CONVERT(bigint,  valor))) >= 6 -- 6 ou mais dígitos numéricos '000000123456'
--					OR
--					len(convert(varchar, TRY_CONVERT(bigint,  valor))) IS NULL -- Falha ao converter para Big INT '12856510658165165156'
--				) 
--			)
--		)
--		AND desconsiderar_nos_agrupamentos = 0 THEN valor ELSE '' END as ean_longo,

--		CASE WHEN 
--		(

--				/* ------------------------------- Eans curtos ------------------------------- */

--				(
--					len(valor) BETWEEN 3 AND 4 -- EANS de 3 a 4 dígitos
--					and valor LIKE '%[^0-9]%' -- EANS que contén letras
--				)
--				OR
--				(
--					len(valor) BETWEEN 4 AND 6 -- EANS de 3 a 6 dígitos
--					and valor NOT LIKE '%[^0-9]%' -- EANS que contén números
--				)	
--				OR
--				(
--					len(valor) >= 7 -- EANS com mais de 7 dígitos
--					AND valor NOT LIKE '%[^0-9]%' -- EANS que contén números
--					AND len(convert(varchar, TRY_CONVERT(bigint,  valor))) <= 5 -- 5 ou menos dígitos numéricos '1000000012345'
--				)

--				/* ------------------------------- Eans curtos ------------------------------- */
--			) AND desconsiderar_nos_agrupamentos = 0 THEN valor ELSE '' END as ean_curto


--	from nlp_data_lake.dbo.CrawlerNewProductDetail p with (nolock) 
--	left join nlp_data_lake.dbo.CrawlerNewProductDetailEAN e with (nolock) on e.idCrawlerNewProductDetail = p.id
--	inner join nlp_management.dbo.Source s with (nolock) on s.id = p.sourceId
--	--LEFT JOIN  [nlp_data_lake].dbo.[temp_flat-table_product_detail] t on t.id = p.id
--	where		
--		s.active = 1
		
	
--) as tb
--LEFT JOIN  [nlp_data_lake].dbo.[temp_flat-table_product_detail] t on t.id = tb.id AND (t.ean_curto = tb.ean_curto AND t.ean_longo = tb.ean_longo)
--WHERE
--	t.id IS NULL	



--INSERT [nlp_data_lake].dbo.[temp_flat-table_product_detail] (id, productName, productUrl, productGroupId, productName_fingerprint, productName_metaphone, productName_ngram, productName_tokenizada, productName_tokenizada_fingerprint,feed_brand, feed_brand_tokenizada, feed_brand_ngram, feed_brand_fingerprint, productImage_hash_Imagio_ComputeHash, productImage_sem_imagem_desconsiderar, productPrice, productRodouRotinaGroup, ean_longo, ean_curto, ean_curto_feed_brand,ean_curto_feed_brand_ngram,ean_curto_feed_brand_fingerprint,ean_curto_feed_brand_tokenizada)
--select * from #pendenteInserir2






/* ---------------------------------------- 0: Dá UPDATE nos EAN's pra ignorar   ---------------------------------------- */
/*


-- update nlp_data_lake.dbo.CrawlerNewProductDetailEAN set desconsiderar_nos_agrupamentos = 1 where isnull(desconsiderar_nos_agrupamentos, 0) = 0 AND valor in ('SEM GTIN', '1000000000000', 'null','0','None', 'N/A', '#N/A', '---') 
select count(*) from nlp_data_lake.dbo.CrawlerNewProductDetailEAN where desconsiderar_nos_agrupamentos = 0 AND valor in ('SEM GTIN', '1000000000000', 'null','0','None', 'N/A', '#N/A', '---') 


update nlp_data_lake.dbo.CrawlerNewProductDetailEAN set desconsiderar_nos_agrupamentos = 1 where desconsiderar_nos_agrupamentos = 0 and valor in (
-- select * from nlp_data_lake.dbo.CrawlerNewProductDetailEAN where desconsiderar_nos_agrupamentos = 0 and valor in (

	-- Eans com mais de 5 itens, em um só site
	select 
		c.valor
	from nlp_data_lake.dbo.CrawlerNewProductDetailEAN c
	inner join nlp_data_lake.dbo.CrawlerNewProductDetail p with (nolock)  on p.id = c.idCrawlerNewProductDetail
	group by
		c.valor
	having
		count(*) > 5 -- Mais de 5 produtos
		and count(distinct p.sourceId) = 1 -- Apenas um site
	

	UNION ALL

	-- Eans somente com letras
	select 
		c.valor
	from nlp_data_lake.dbo.CrawlerNewProductDetailEAN c
	inner join nlp_data_lake.dbo.CrawlerNewProductDetail p with (nolock)  on p.id = c.idCrawlerNewProductDetail
	where
		valor NOT LIKE '%[0-9]%' -- EANS que não contén números
	group by
		c.valor
	having
		count(*) > 1 -- Mais de 1 produto


	UNION ALL

	-- Eans com '+', truncados (90E+12)
	select 
		c.valor
	from nlp_data_lake.dbo.CrawlerNewProductDetailEAN c
	inner join nlp_data_lake.dbo.CrawlerNewProductDetail p with (nolock)  on p.id = c.idCrawlerNewProductDetail
	where
		valor LIKE '%+%'
	group by
		c.valor
	having
		count(*) > 1 -- Mais de 1 produto
	

)




*/



-- Remove tabelas temporárias
DROP TABLE IF EXISTS tempdb.dbo.#dados_produtos_relacionados
DROP TABLE IF EXISTS tempdb.dbo.#dados_produtos_relacionados_aos_relacionados
DROP TABLE IF EXISTS #palavrasTokenizadasSeparadas
DROP TABLE IF EXISTS tempdb.dbo.#nomesProdutos
DROP TABLE IF EXISTS #log_tempo
DROP TABLE IF EXISTS #idsParaDesconsiderar_antes





/* ---------------------------------------- 0: UPDATE Normaliza Brands  ---------------------------------------- */

-- Normalizar Brand, antes de agrupar is grupos, pois o agrupamento de gruopos usa o brand para agrupar também
-- normaliza_brands_e_insere_nos_grupos_pai.sql


/* ---------------------------------------- 0: INSERT Insere EAN's com base nas características do produto  ---------------------------------------- */

/*

-- Características mais usadas
select chave, format(count(*),'0,0'), MIN(valor), MAX(valor) from nlp_data_lake.dbo.CrawlerNewProductDetailCaracteristica 
where
	 valor not in ('','-')
group by
	chave
having	
	COUNT(*) > 10
order by
	COUNT(*) desc

*/

/*
select distinct
	pe.id,
	pc.valor as valor_na_caracteristica
into #eansParaSetar1
from nlp_data_lake.dbo.CrawlerNewProductDetailCaracteristica pc with (nolock)
inner join nlp_data_lake.dbo.CrawlerNewProductDetail pe with (nolock) on pe.id = pc.idCrawlerNewProductDetail
left join nlp_data_lake.dbo.CrawlerNewProductDetailEAN e with (nolock) on e.idCrawlerNewProductDetail = pe.id
where 
	pc.chave IN ('Isbn-13', 'Gtin-13','Isbn-10', 'Código do Fabricante','Referência do Produto')
	and (
		e.id is null -- Sem EAN
	)


-- Insere
INSERT INTO nlp_data_lake.dbo.CrawlerNewProductDetailEAN (idCrawlerNewProductDetail, valor)
select id, valor_na_caracteristica from #eansParaSetar1


drop table #eansParaSetar1
*/

/* ------------------------------------ 0: Limpa tentativas de agrupamento ------------------------------------ */

/*

DELETE FROM nlp_data_lake.dbo.temp_agrupamentos_ignorados

TRUNCATE TABLE [nlp_data_lake].[dbo].[ProductGroup]   

WHILE 1 = 1
BEGIN
   UPDATE TOP(500000) nlp_data_lake.dbo.CrawlerNewProductDetail set productRodouRotinaGroup = 0, productGroupId = NULL, productGroupRelationType = NULL, productGroupRelationValue = NULL WHERE productGroupId IS NOT NULL

   --- select  top 1 * from nlp_data_lake.dbo.CrawlerNewProductDetail WHERE productGroupId IS NOT NULL
   --- select  count(*) from nlp_data_lake.dbo.CrawlerNewProductDetail WHERE productGroupId > 0

   IF @@ROWCOUNT < 500000 BREAK;

END

*/


-- BEGIN TRAN

DECLARE
	@rodou BIT = 0

DECLARE @StartTimeGeral datetime=GETDATE() 
DECLARE @EndTimeGeral datetime
		

CREATE TABLE #log_tempo (
	productId INT,
	tipo NVARCHAR(500),
	tempo INT
)

/* ------------------------------------ 1: Roda tentativa de agrupamento ------------------------------------ */

DECLARE
	@productId INT,
	@productName NVARCHAR(500),
	@productName_fingerprint VARCHAR(500),
	@productName_metaphone VARCHAR(500),
	@productName_ngram VARCHAR(500),
	@productName_tokenizada_raw VARCHAR(500),
	@productName_tokenizada_fingerprint VARCHAR(500),
	@ean_longo VARCHAR(500),
	@ean_curto VARCHAR(500),
	@productUrl VARCHAR(1500),
	@feed_brand NVARCHAR(500),
	@feed_brand_tokenizada VARCHAR(500),
	@feed_brand_ngram VARCHAR(500),
	@feed_brand_fingerprint VARCHAR(500),
	@productImage_hash_Imagio_ComputeHash VARCHAR(100)


DECLARE product_cursor CURSOR FOR

	
	-- Varre produtos ainda não relacionados		
	SELECT 
		id,
		productName,
		productName_fingerprint,
		productName_metaphone,
		productName_ngram,
		productName_tokenizada,
		productName_tokenizada_fingerprint,
		ean_longo,
		ean_curto,
		productUrl,
		feed_brand,
		feed_brand_tokenizada,
		feed_brand_ngram,
		feed_brand_fingerprint,
		CASE WHEN productImage_sem_imagem_desconsiderar = 0 THEN productImage_hash_Imagio_ComputeHash ELSE '' END as productImage_hash_Imagio_ComputeHash
	FROM [nlp_data_lake].dbo.[temp_flat-table_product_detail]
	where
		productGroupId IS NULL -- Ainda não está relacionado a nenhum grupo de produtos
		AND ISNULL(productRodouRotinaGroup, 0) = 0 -- Ainda não rodou rotina de agrupamento para esse produto
		AND productName <> ''
	-- AND id IN (4980861,4980862,4980864,4980865)
	--and productName like '%|*%' escape '|'
	 
OPEN product_cursor  
FETCH NEXT FROM product_cursor INTO @productId, @productName, @productName_fingerprint, @productName_metaphone, @productName_ngram, @productName_tokenizada_raw, @productName_tokenizada_fingerprint, @ean_longo, @ean_curto, @productUrl, @feed_brand, @feed_brand_tokenizada, @feed_brand_ngram, @feed_brand_fingerprint, @productImage_hash_Imagio_ComputeHash

WHILE @@FETCH_STATUS = 0
BEGIN  

	
	IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES (@productId);

	IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES (@productName);

	-- SELECT @productId, @productName, @productName_fingerprint, @productName_metaphone, @productName_ngram, @productName_tokenizada_raw, @productName_tokenizada_fingerprint, @ean_longo, @ean_curto, @productUrl, @feed_brand, @feed_brand_tokenizada, @feed_brand_ngram, @feed_brand_fingerprint, @productImage_hash_Imagio_ComputeHash

	IF 1 = 1 BEGIN

	if @rodou = 0
	BEGIN
		SET @StartTimeGeral =GETDATE() 
		SET @rodou = 1
	END

	-- SELECT @productName

	DECLARE @StartTime datetime=GETDATE() 
	DECLARE @EndTime datetime
	
	
	


	-- CLOSE product_cursor  
	-- DEALLOCATE product_cursor  
		
	

	-- Verifica se o produto atual já foi relacionado
	IF (
		select TOP 1 1 from [nlp_data_lake].dbo.[temp_flat-table_product_detail]
		where
			id = @productId 
			AND (
				productRodouRotinaGroup = 1 
				OR 
				productGroupId > 0
			)
		) IS NULL -- Se não rodou rotina de agrupamento para esse produto
	BEGIN
	
		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('2');
		
	
		/* ----------------------------------------- 3º Pega produtos relacionados, e seus dados individuais  ----------------------------------------- */

		-- DROP TABLE #dados_produtos_relacionados 

		CREATE TABLE #dados_produtos_relacionados (
			tipo NVARCHAR(100),
			valor NVARCHAR(500),
			id INT,
			productName NVARCHAR(1500),
			productGroupId INT,
			productName_fingerprint NVARCHAR(500),
			productName_metaphone NVARCHAR(500),
			productName_ngram NVARCHAR(500),
			productName_tokenizada_raw NVARCHAR(500),
			productName_tokenizada_fingerprint NVARCHAR(500),
			ean_longo NVARCHAR(500),
			ean_curto NVARCHAR(500),
			productUrl NVARCHAR(1500),
			feed_brand NVARCHAR(500),
			feed_brand_tokenizada NVARCHAR(500),
			feed_brand_ngram NVARCHAR(500),
			feed_brand_fingerprint NVARCHAR(500),
			productImage_hash_Imagio_ComputeHash NVARCHAR(100),
			productPrice DECIMAL(18,2)
		)

		CREATE TABLE #dados_produtos_relacionados_aos_relacionados (
			id INT,
			productName NVARCHAR(1500),
			productGroupId INT,
			tipo NVARCHAR(100),
			valor NVARCHAR(500),		
			productPrice DECIMAL(18,2),	
			productImage_hash_Imagio_ComputeHash NVARCHAR(100),
			productUrl NVARCHAR(1500),
			productName_fingerprint NVARCHAR(500),
			productName_metaphone NVARCHAR(500),
			productName_ngram NVARCHAR(500),
			productName_tokenizada_fingerprint NVARCHAR(500),
			productName_hash NVARCHAR(500),
			tipoProdutoOrigem NVARCHAR(100),
			valorProdutoOrigem NVARCHAR(500)
		)


		-- EAN longo
		INSERT INTO #dados_produtos_relacionados
		select 
			'EAN longo' as tipo,
			@ean_longo as valor,
			id,
			productName,
			productGroupId,
			productName_fingerprint,
			productName_metaphone,
			productName_ngram,			
			productName_tokenizada as productName_tokenizada_raw,
			productName_tokenizada_fingerprint,
			ean_longo,
			ean_curto,
			productUrl,
			feed_brand,
			feed_brand_tokenizada,
			feed_brand_ngram,
			feed_brand_fingerprint,
			productImage_hash_Imagio_ComputeHash,
			productPrice		
		from [nlp_data_lake].dbo.[temp_flat-table_product_detail] with (nolock) 
		where
			ean_longo = @ean_longo
			and @ean_longo <> ''

		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 1: EAN LONGO', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
			

			SELECT @StartTime=GETDATE() 

		END

		

		-- productName
		INSERT INTO #dados_produtos_relacionados
		select 
			'productName' as tipo,
			@productName as valor,
			id,
			productName,
			productGroupId,
			productName_fingerprint,
			productName_metaphone,
			productName_ngram,			
			productName_tokenizada as productName_tokenizada_raw,
			productName_tokenizada_fingerprint,
			ean_longo,
			ean_curto,
			productUrl,
			feed_brand,
			feed_brand_tokenizada,
			feed_brand_ngram,
			feed_brand_fingerprint,
			productImage_hash_Imagio_ComputeHash,
			productPrice		
		from [nlp_data_lake].dbo.[temp_flat-table_product_detail] with (nolock) 
		where
			productName = @productName
			and @productName <> ''


		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 1: ProductName', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
			

			SELECT @StartTime=GETDATE() 

		END

		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('3');
		

		-- productName_fingerprint
		INSERT INTO #dados_produtos_relacionados
		select 
			'productName_fingerprint' as tipo,
			@productName_fingerprint as valor,
			id,
			productName,
			productGroupId,
			productName_fingerprint,
			productName_metaphone,
			productName_ngram,			
			productName_tokenizada as productName_tokenizada_raw,
			productName_tokenizada_fingerprint,
			ean_longo,
			ean_curto,
			productUrl,
			feed_brand,
			feed_brand_tokenizada,
			feed_brand_ngram,
			feed_brand_fingerprint,
			productImage_hash_Imagio_ComputeHash,
			productPrice		
		from [nlp_data_lake].dbo.[temp_flat-table_product_detail] with (nolock) 
		where
			productName_fingerprint = @productName_fingerprint
			and @productName_fingerprint <> ''
	

		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 1: ProductNameFingerprint', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
			

			SELECT @StartTime=GETDATE() 

		END

		-- productName_metaphone
		INSERT INTO #dados_produtos_relacionados
		select 
			'productName_metaphone' as tipo,
			@productName_metaphone as valor,
			id,
			productName,
			productGroupId,
			productName_fingerprint,
			productName_metaphone,
			productName_ngram,			
			productName_tokenizada as productName_tokenizada_raw,
			productName_tokenizada_fingerprint,
			ean_longo,
			ean_curto,
			productUrl,
			feed_brand,
			feed_brand_tokenizada,
			feed_brand_ngram,
			feed_brand_fingerprint,
			productImage_hash_Imagio_ComputeHash,
			productPrice		
		from [nlp_data_lake].dbo.[temp_flat-table_product_detail] with (nolock) 
		where
			productName_metaphone = @productName_metaphone
			and LEN(@productName_metaphone) > 3
			AND REPLACE(productName, '*', '|') like '% %' ESCAPE '|' /* Com mais de 3 caracteres no metaphone, e pelo menos 1 espaço no nome */
			
		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 1: ProductNameMetaphone', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
			

			SELECT @StartTime=GETDATE() 

		END


	
		-- productName_ngram
		INSERT INTO #dados_produtos_relacionados
		select 
			'productName_ngram' as tipo,
			@productName_ngram as valor,
			id,
			productName,
			productGroupId,
			productName_fingerprint,
			productName_metaphone,
			productName_ngram,			
			productName_tokenizada as productName_tokenizada_raw,
			productName_tokenizada_fingerprint,
			ean_longo,
			ean_curto,
			productUrl,
			feed_brand,
			feed_brand_tokenizada,
			feed_brand_ngram,
			feed_brand_fingerprint,
			productImage_hash_Imagio_ComputeHash,
			productPrice		
		from [nlp_data_lake].dbo.[temp_flat-table_product_detail] with (nolock) 
		where
			productName_ngram = @productName_ngram
			and @productName_ngram <> ''
	

		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 1: ProductNameNgram', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
			

			SELECT @StartTime=GETDATE() 

		END

		-- productName_tokenizada_fingerprint
		INSERT INTO #dados_produtos_relacionados
		select 
			'productName_tokenizada_fingerprint' as tipo,
			@productName_tokenizada_fingerprint as valor,
			id,
			productName,
			productGroupId,
			productName_fingerprint,
			productName_metaphone,
			productName_ngram,			
			productName_tokenizada as productName_tokenizada_raw,
			productName_tokenizada_fingerprint,
			ean_longo,
			ean_curto,
			productUrl,
			feed_brand,
			feed_brand_tokenizada,
			feed_brand_ngram,
			feed_brand_fingerprint,
			productImage_hash_Imagio_ComputeHash,
			productPrice		
		from [nlp_data_lake].dbo.[temp_flat-table_product_detail] with (nolock) 
		where
			productName_tokenizada_fingerprint = @productName_tokenizada_fingerprint
			and @productName_tokenizada_fingerprint like '% %' /* Com 1 espaço em branco no meio  */

		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 1: ProductNameTokenizadaFingerprint', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
			

			SELECT @StartTime=GETDATE() 

		END

		-- productUrl
		INSERT INTO #dados_produtos_relacionados
		select 
			'productUrl' as tipo,
			@productUrl as valor,
			id,
			productName,
			productGroupId,
			productName_fingerprint,
			productName_metaphone,
			productName_ngram,			
			productName_tokenizada as productName_tokenizada_raw,
			productName_tokenizada_fingerprint,
			ean_longo,
			ean_curto,
			productUrl,
			feed_brand,
			feed_brand_tokenizada,
			feed_brand_ngram,
			feed_brand_fingerprint,
			productImage_hash_Imagio_ComputeHash,
			productPrice		
		from [nlp_data_lake].dbo.[temp_flat-table_product_detail] with (nolock) 
		where
			productUrl = @productUrl
			and @productUrl <> ''
		

		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 1: ProductURL', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
			

			SELECT @StartTime=GETDATE() 

		END

		-- EAN curto + Brand
		INSERT INTO #dados_produtos_relacionados		
		select 
			'EAN curto + Brand' as tipo,
			@ean_curto + '/' + @feed_brand as valor,
			id,
			productName,
			productGroupId,
			productName_fingerprint,
			productName_metaphone,
			productName_ngram,			
			productName_tokenizada as productName_tokenizada_raw,
			productName_tokenizada_fingerprint,
			ean_longo,
			ean_curto,
			productUrl,
			feed_brand,
			feed_brand_tokenizada,
			feed_brand_ngram,
			feed_brand_fingerprint,
			productImage_hash_Imagio_ComputeHash,
			productPrice		
		from [nlp_data_lake].dbo.[temp_flat-table_product_detail] with (nolock) 
		where
			ean_curto = @ean_curto and @ean_curto <> ''
			AND feed_brand = @feed_brand and @feed_brand <> '' and LEN(feed_brand) >= 3 and feed_brand not in ('brand','importado','Produto Importado','Original', '-','Não Informado','Indisponível','N/a','N/D')
	
		

		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 1: EAN curto + Brand', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
			

			SELECT @StartTime=GETDATE() 

		END

		-- EAN curto + Brand tokenizada
		INSERT INTO #dados_produtos_relacionados
		select 
			'EAN curto + Brand tokenizada' as tipo,
			@ean_curto + '/' + @feed_brand_tokenizada as valor,
			id,
			productName,
			productGroupId,
			productName_fingerprint,
			productName_metaphone,
			productName_ngram,			
			productName_tokenizada as productName_tokenizada_raw,
			productName_tokenizada_fingerprint,
			ean_longo,
			ean_curto,
			productUrl,
			feed_brand,
			feed_brand_tokenizada,
			feed_brand_ngram,
			feed_brand_fingerprint,
			productImage_hash_Imagio_ComputeHash,
			productPrice		
		from [nlp_data_lake].dbo.[temp_flat-table_product_detail] with (nolock) 
		where
			ean_curto = @ean_curto and @ean_curto <> ''
			AND feed_brand_tokenizada = @feed_brand_tokenizada and @feed_brand_tokenizada <> '' and feed_brand_tokenizada not in ('brand','import','produt import','original', 'nao inform', 'indispon') and LEN(feed_brand) >= 3
	
		
		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 1: EAN curto + Brand tokenizada', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
			

			SELECT @StartTime=GETDATE() 

		END


		-- EAN curto + Brand fingerprint
		INSERT INTO #dados_produtos_relacionados
		select 
			'EAN curto + Brand fingerprint' as tipo,
			@ean_curto + '/' + @feed_brand_fingerprint as valor,
			id,
			productName,
			productGroupId,
			productName_fingerprint,
			productName_metaphone,
			productName_ngram,			
			productName_tokenizada as productName_tokenizada_raw,
			productName_tokenizada_fingerprint,
			ean_longo,
			ean_curto,
			productUrl,
			feed_brand,
			feed_brand_tokenizada,
			feed_brand_ngram,
			feed_brand_fingerprint,
			productImage_hash_Imagio_ComputeHash,
			productPrice		
		from [nlp_data_lake].dbo.[temp_flat-table_product_detail] with (nolock) 
		where
			ean_curto = @ean_curto and @ean_curto <> ''
			AND feed_brand_fingerprint = @feed_brand_fingerprint and @feed_brand_fingerprint like '% % %'  /* Com 2 espaços em branco no meio  */ 
	
		

		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 1: EAN curto + Brand fingerprint', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
			

			SELECT @StartTime=GETDATE() 

		END


		-- EAN curto + Brand ngram
		INSERT INTO #dados_produtos_relacionados
		select 
			'EAN curto + Brand ngram' as tipo,
			@ean_curto + '/' + @feed_brand_ngram as valor,
			id,
			productName,
			productGroupId,
			productName_fingerprint,
			productName_metaphone,
			productName_ngram,			
			productName_tokenizada as productName_tokenizada_raw,
			productName_tokenizada_fingerprint,
			ean_longo,
			ean_curto,
			productUrl,
			feed_brand,
			feed_brand_tokenizada,
			feed_brand_ngram,
			feed_brand_fingerprint,
			productImage_hash_Imagio_ComputeHash,
			productPrice		
		from [nlp_data_lake].dbo.[temp_flat-table_product_detail] with (nolock) 
		where
			ean_curto = @ean_curto and @ean_curto <> ''
			AND feed_brand_ngram = @feed_brand_ngram
			and feed_brand_ngram not in ('iaddoduimmpo odorpoprrorttatout','anbrndra','addoimmporportta','algiiginnaorri''iadaodofoinmananfo orrm', 'dielinisivndnionpospve', 'an', 'dn') 
			and @feed_brand_ngram <> ''
			and LEN(feed_brand) >= 3
			

		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 1: EAN curto + Brand ngram', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
			

			SELECT @StartTime=GETDATE() 

		END
		
		-- productImage_hash_Imagio_ComputeHash
		INSERT INTO #dados_produtos_relacionados
		select 
			'productImage_hash_Imagio_ComputeHash' as tipo,
			@productImage_hash_Imagio_ComputeHash as valor,
			id,
			productName,
			productGroupId,
			productName_fingerprint,
			productName_metaphone,
			productName_ngram,			
			productName_tokenizada as productName_tokenizada_raw,
			productName_tokenizada_fingerprint,
			ean_longo,
			ean_curto,
			productUrl,
			feed_brand,
			feed_brand_tokenizada,
			feed_brand_ngram,
			feed_brand_fingerprint,
			productImage_hash_Imagio_ComputeHash,
			productPrice		
		from [nlp_data_lake].dbo.[temp_flat-table_product_detail] with (nolock) 
		where
			productImage_hash_Imagio_ComputeHash = @productImage_hash_Imagio_ComputeHash
			and @productImage_hash_Imagio_ComputeHash <> ''
			-- AND productImage_sem_imagem_desconsiderar = 0
			
		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 1: productImage_hash_Imagio_ComputeHash', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
			

			SELECT @StartTime=GETDATE() 

		END

		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('4');

		

		/*
		-- Limpa relações

		update nlp_data_lake.dbo.CrawlerNewProductDetail 
		set productId = null, productParentRelationType = null, productParentRelationValue = null, productGroupId = null, productGroupRelationType = null, productGroupRelationValue = null
		where productImage_hash_Imagio_ComputeHash = '571901361761815080151173158618015836242312261113130193164191048151861351517637215'
	
		*/	

		
		
		
		
		/* ---------------- Remove termos que não fazem parte do grupo (não possuem palavras semelhantes) (verificação/remoção apenas em termos que são relacionados ao EAN, pois vem muito erro dos marketplaces) ----------- */

		-- Separa as palavras tokenizadas
		select data as palavra into #palavrasTokenizadasSeparadas from nlp.dbo.converteArrayParaTabela(@productName_tokenizada_raw, ' ') 
		where 
			data <> ''

			
		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('5');


		SELECT distinct 
			t3.id,
			t3.productName,
			t3.productName_tokenizada_fingerprint,
			t3.tipo,
			t3.valor
		INTO #idsParaDesconsiderar_antes
		FROM #dados_produtos_relacionados t3
		WHERE 
			NOT EXISTS (

				select top 1 1 from nlp.dbo.converteArrayParaTabela(productName_tokenizada_raw, ' ') t1
				where exists (	
					
					select top 1 1 from #palavrasTokenizadasSeparadas t2
					 where 
						t2.palavra = t1.data
						OR t2.palavra LIKE '%' + t1.data + '%'
						OR t1.data LIKE '%' + t2.palavra + '%'
				)
				and t1.data <> ''
			)
			/*(

				select COUNT(*) from nlp.dbo.converteArrayParaTabela(productName_tokenizada_raw, ' ') t1
				where exists (	
					
					select top 1 1 from #palavrasTokenizadasSeparadas t2
					 where 
						t2.palavra = t1.data
						OR t2.palavra LIKE '%' + t1.data + '%'
						OR t1.data LIKE '%' + t2.palavra + '%'
				)
				and t1.data <> ''
			) <= 1 -- Se não tem pelo menos 2 caracteres semelhamtes, remove
			*/
			AND tipo = 'EAN longo' -- Faz a verificação/remoção apenas em termos que são relacionados ao EAN, pois vem muito erro dos marketplaces

			
			
		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('6');


		-- Grava Log, informando qe o agrupamento será desconsiderado
		INSERT INTO nlp_data_lake.dbo.temp_agrupamentos_ignorados (productName_origem, productName_tokenizada_origem, productName,productName_tokenizada, tipo, valor)
		SELECT @productName, @productName_tokenizada_raw,productName,productName_tokenizada_fingerprint,tipo,valor FROM #idsParaDesconsiderar_antes


		
		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('7');


		-- Desconsidera produto no agrupamento
		DELETE FROM #dados_produtos_relacionados WHERE  id in (
			SELECT id FROM #idsParaDesconsiderar_antes
		)

		
		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('8');

		
		DROP TABLE #idsParaDesconsiderar_antes

		
		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('9');


		/* ---------------- Remove termos que não fazem parte do grupo (não possuem palavras semelhantes) (verificação/remoção apenas em termos que são relacionados ao EAN, pois vem muito erro dos marketplaces) ----------- */

		


		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 2', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
		
			SELECT @StartTime=GETDATE() 

		END

		/*
		TEMP - Remover
		drop table #palavrasTokenizadasSeparadas
		drop table #dados_produtos_relacionados
		CLOSE product_cursor  
		DEALLOCATE product_cursor  
		*/
			
		/* ----------------------------------------------------------- Remove termos que não fazem parte do grupo (não possuem palavras semelhantes) ----------------------------------------------------------- */


		
		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('10');




		/*

		
		-- EAN longo
		select p.id, p.productName, p.productGroupId, 'EAN longo' as tipo, p.ean_longo as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem  from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		INNER JOIN #dados_produtos_relacionados t2 on t2.ean_longo = p.ean_longo and p.ean_longo <> ''

		-- productName
		select p.id, p.productName, p.productGroupId, 'productName' as tipo, '' as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock) 
		INNER JOIN #dados_produtos_relacionados t2 on t2.productName = p.productName and p.productName <> ''
		
		-- productName_fingerprint
		select p.id, p.productName, p.productGroupId, 'productName_fingerprint' as tipo, p.productName_fingerprint as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		INNER JOIN #dados_produtos_relacionados t2 on t2.productName_fingerprint = p.productName_fingerprint and p.productName_fingerprint <> ''

		-- productName_metaphone
		select p.id, p.productName, p.productGroupId, 'productName_metaphone' as tipo, p.productName_metaphone as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		INNER JOIN #dados_produtos_relacionados t2 on t2.productName_metaphone = p.productName_metaphone and p.productName_metaphone <> ''

		-- productName_ngram
		select p.id, p.productName, p.productGroupId, 'productName_ngram' as tipo, p.productName_ngram as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		INNER JOIN #dados_produtos_relacionados t2 on t2.productName_ngram = p.productName_ngram and p.productName_ngram <> ''

		-- productName_tokenizada_fingerprint
		select p.id, p.productName, p.productGroupId, 'productName_tokenizada_fingerprint' as tipo, p.productName_tokenizada_fingerprint as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		INNER JOIN #dados_produtos_relacionados t2 on t2.productName_tokenizada_fingerprint = p.productName_tokenizada_fingerprint and p.productName_tokenizada_fingerprint <> ''

		-- productUrl
		select p.id, p.productName, p.productGroupId, 'productUrl' as tipo, p.productUrl as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		INNER JOIN #dados_produtos_relacionados t2 on t2.productUrl = p.productUrl and p.productUrl <> ''

		-- EAN curto + Brand
		select p.id, p.productName, p.productGroupId, 'EAN curto + Brand' as tipo, p.ean_curto + '/' + p.feed_brand as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		INNER JOIN #dados_produtos_relacionados t2 on t2.ean_curto <> ''  AND t2.ean_curto = p.ean_curto AND t2.feed_brand <> '' AND t2.feed_brand = p.feed_brand and LEN(t2.feed_brand) >= 3

		-- EAN curto + Brand tokenizada
		select p.id, p.productName, p.productGroupId, 'EAN curto + Brand tokenizada' as tipo, p.ean_curto + '/' + p.feed_brand_tokenizada as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		INNER JOIN #dados_produtos_relacionados t2 on t2.ean_curto <> '' AND t2.ean_curto = p.ean_curto AND t2.feed_brand_tokenizada <> '' AND t2.feed_brand_tokenizada = p.feed_brand_tokenizada and LEN(t2.feed_brand) >= 3

		-- EAN curto + Brand fingerprint
		select p.id, p.productName, p.productGroupId, 'EAN curto + Brand fingerprint' as tipo, p.ean_curto + '/' + p.feed_brand_fingerprint as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		INNER JOIN #dados_produtos_relacionados t2 on t2.ean_curto <> '' AND t2.ean_curto = p.ean_curto AND t2.feed_brand_fingerprint <> '' AND t2.feed_brand_fingerprint = p.feed_brand_fingerprint and LEN(t2.feed_brand) >= 3

		-- EAN curto + Brand ngram
		select p.id, p.productName, p.productGroupId, 'EAN curto + Brand ngram' as tipo, p.ean_curto + '/' + p.feed_brand_ngram as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		INNER JOIN #dados_produtos_relacionados t2 ON t2.ean_curto <> '' AND t2.ean_curto = p.ean_curto AND t2.feed_brand_ngram <> '' AND t2.feed_brand_ngram = p.feed_brand_ngram and LEN(t2.feed_brand) >= 3

		-- productImage_hash_Imagio_ComputeHash
		select p.id, p.productName, p.productGroupId, 'productImage_hash_Imagio_ComputeHash' as tipo, p.productImage_hash_Imagio_ComputeHash as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		INNER JOIN #dados_produtos_relacionados t2 ON t2.productImage_hash_Imagio_ComputeHash = p.productImage_hash_Imagio_ComputeHash and t2.productImage_hash_Imagio_ComputeHash <> ''
		where
			p.productImage_sem_imagem_desconsiderar = 0


		*/

		




		-- select * from #dados_produtos_relacionados

		-- select * from #dados_produtos_relacionados_aos_relacionados

		

		/* ---------------------------------------------------- 4º Pega todos os produtos relacionados aos dados individuais coletados ---------------------------------------------------- */


		-- select * from #dados_produtos_relacionados

		---- EAN longo
		--select p.id, p.productName, p.productGroupId, 'EAN longo' as tipo, p.ean_longo as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem into #dados_produtos_relacionados_aos_relacionados from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		--INNER JOIN #dados_produtos_relacionados t2 on t2.ean_longo = p.ean_longo and p.ean_longo <> ''
		
		--UNION 

		---- productName
		--select p.id, p.productName, p.productGroupId, 'productName' as tipo, '' as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock) 
		--INNER JOIN #dados_produtos_relacionados t2 on t2.productName = p.productName and p.productName <> ''
		
		--UNION 

		---- productName_fingerprint
		--select p.id, p.productName, p.productGroupId, 'productName_fingerprint' as tipo, p.productName_fingerprint as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		--INNER JOIN #dados_produtos_relacionados t2 on t2.productName_fingerprint = p.productName_fingerprint and p.productName_fingerprint <> ''
		

		--UNION 

		---- productName_metaphone
		--select p.id, p.productName, p.productGroupId, 'productName_metaphone' as tipo, p.productName_metaphone as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		--INNER JOIN #dados_produtos_relacionados t2 on t2.productName_metaphone = p.productName_metaphone and p.productName_metaphone <> ''
			

		--UNION 

		---- productName_ngram
		--select p.id, p.productName, p.productGroupId, 'productName_ngram' as tipo, p.productName_ngram as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		--INNER JOIN #dados_produtos_relacionados t2 on t2.productName_ngram = p.productName_ngram and p.productName_ngram <> ''
			

		--UNION 

		---- productName_tokenizada_fingerprint
		--select p.id, p.productName, p.productGroupId, 'productName_tokenizada_fingerprint' as tipo, p.productName_tokenizada_fingerprint as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		--INNER JOIN #dados_produtos_relacionados t2 on t2.productName_tokenizada_fingerprint = p.productName_tokenizada_fingerprint and p.productName_tokenizada_fingerprint <> ''
	
		--UNION 

		---- productUrl
		--select p.id, p.productName, p.productGroupId, 'productUrl' as tipo, p.productUrl as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		--INNER JOIN #dados_produtos_relacionados t2 on t2.productUrl = p.productUrl and p.productUrl <> ''

		--UNION 

		---- EAN curto + Brand
		--select p.id, p.productName, p.productGroupId, 'EAN curto + Brand' as tipo, p.ean_curto + '/' + p.feed_brand as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		--INNER JOIN #dados_produtos_relacionados t2 on t2.ean_curto <> ''  AND t2.ean_curto = p.ean_curto AND t2.feed_brand <> '' AND t2.feed_brand = p.feed_brand and LEN(t2.feed_brand) >= 3

		--UNION 

		---- EAN curto + Brand tokenizada
		--select p.id, p.productName, p.productGroupId, 'EAN curto + Brand tokenizada' as tipo, p.ean_curto + '/' + p.feed_brand_tokenizada as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		--INNER JOIN #dados_produtos_relacionados t2 on t2.ean_curto <> '' AND t2.ean_curto = p.ean_curto AND t2.feed_brand_tokenizada <> '' AND t2.feed_brand_tokenizada = p.feed_brand_tokenizada and LEN(t2.feed_brand) >= 3

		--UNION 

		---- EAN curto + Brand fingerprint
		--select p.id, p.productName, p.productGroupId, 'EAN curto + Brand fingerprint' as tipo, p.ean_curto + '/' + p.feed_brand_fingerprint as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		--INNER JOIN #dados_produtos_relacionados t2 on t2.ean_curto <> '' AND t2.ean_curto = p.ean_curto AND t2.feed_brand_fingerprint <> '' AND t2.feed_brand_fingerprint = p.feed_brand_fingerprint and LEN(t2.feed_brand) >= 3
		

		--UNION 

		---- EAN curto + Brand ngram
		--select p.id, p.productName, p.productGroupId, 'EAN curto + Brand ngram' as tipo, p.ean_curto + '/' + p.feed_brand_ngram as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		--INNER JOIN #dados_produtos_relacionados t2 ON t2.ean_curto <> '' AND t2.ean_curto = p.ean_curto AND t2.feed_brand_ngram <> '' AND t2.feed_brand_ngram = p.feed_brand_ngram and LEN(t2.feed_brand) >= 3


		--UNION 


		---- productImage_hash_Imagio_ComputeHash
		--select p.id, p.productName, p.productGroupId, 'productImage_hash_Imagio_ComputeHash' as tipo, p.productImage_hash_Imagio_ComputeHash as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from [nlp_data_lake].dbo.[temp_flat-table_product_detail] p with (nolock)
		--INNER JOIN #dados_produtos_relacionados t2 ON t2.productImage_hash_Imagio_ComputeHash = p.productImage_hash_Imagio_ComputeHash and t2.productImage_hash_Imagio_ComputeHash <> ''
		--where
		--	p.productImage_sem_imagem_desconsiderar = 0

		

		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('11');

		-- EAN longo
		INSERT INTO #dados_produtos_relacionados_aos_relacionados
		select p.id, p.productName, p.productGroupId, 'EAN longo' as tipo, e.valor as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from nlp_data_lake.dbo.CrawlerNewProductDetail p with (nolock) 
		left join nlp_data_lake.dbo.CrawlerNewProductDetailEAN e with (nolock) on e.idCrawlerNewProductDetail = p.id
		inner join nlp_management.dbo.Source s with (nolock) on s.id = p.sourceId
		INNER JOIN #dados_produtos_relacionados t2 on t2.ean_longo = e.valor and t2.ean_longo <> ''
		where
			s.active = 1 
			
		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('11.1');

		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 2.1: EAN longo', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
		
			SELECT @StartTime=GETDATE() 

		END

		

		-- productName
		INSERT INTO #dados_produtos_relacionados_aos_relacionados
		select p.id, p.productName, p.productGroupId, 'productName' as tipo, '' as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from nlp_data_lake.dbo.CrawlerNewProductDetail p with (nolock) 
		inner join nlp_management.dbo.Source s with (nolock) on s.id = p.sourceId
		INNER JOIN #dados_produtos_relacionados t2 on t2.productName = p.productName and t2.productName <> ''
		where
			s.active = 1 

			IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('11.2');

		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 2.2: productName', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
		
			SELECT @StartTime=GETDATE() 

		END

		-- select productName_fingerprint from #dados_produtos_relacionados

		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('11.3');

		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('11.4: ' + CONVERT(varchar, (select COUNT(*) from #dados_produtos_relacionados_aos_relacionados)));


		-- productName_fingerprint
		INSERT INTO #dados_produtos_relacionados_aos_relacionados	
		select p.id, p.productName, p.productGroupId, 'productName_fingerprint' as tipo, p.productName_fingerprint as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from nlp_data_lake.dbo.CrawlerNewProductDetail p with (nolock) 
		inner join nlp_management.dbo.Source s with (nolock) on s.id = p.sourceId
		-- INNER JOIN #dados_produtos_relacionados t2 on t2.productName_fingerprint = p.productName_fingerprint and t2.productName_fingerprint <> ''
		CROSS APPLY  (
		
			SELECT productName_fingerprint, tipo, MIN(valor) as valor FROM #dados_produtos_relacionados			
			where
				productName_fingerprint <> ''
			group by
				productName_fingerprint, tipo

		) t2 
		where
			s.active = 1 
			and  t2.productName_fingerprint = p.productName_fingerprint

		
		
		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('12');

		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('11.5: ' + CONVERT(varchar, (select COUNT(*) from #dados_produtos_relacionados_aos_relacionados)));


		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 2.2: productName_fingerprint', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
		
			SELECT @StartTime=GETDATE() 

		END
		

		-- productName_metaphone
		INSERT INTO #dados_produtos_relacionados_aos_relacionados	
		select p.id, p.productName, p.productGroupId, 'productName_metaphone' as tipo, p.productName_metaphone as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from nlp_data_lake.dbo.CrawlerNewProductDetail p with (nolock) 
		inner join nlp_management.dbo.Source s with (nolock) on s.id = p.sourceId
		CROSS APPLY  (
		
			SELECT productName_metaphone, tipo, MIN(valor) as valor FROM #dados_produtos_relacionados			
			where
				productName_metaphone <> ''
			group by
				productName_metaphone, tipo

		) t2 
		where
			s.active = 1 
			and  t2.productName_metaphone = p.productName_metaphone

			IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('11.6: ' + CONVERT(varchar, (select COUNT(*) from #dados_produtos_relacionados_aos_relacionados)));

			

		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 2.2: productName_metaphone', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
		
			SELECT @StartTime=GETDATE() 

		END

		-- productName_ngram
		INSERT INTO #dados_produtos_relacionados_aos_relacionados		
		select p.id, p.productName, p.productGroupId, 'productName_ngram' as tipo, p.productName_ngram as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from nlp_data_lake.dbo.CrawlerNewProductDetail p with (nolock) 
		inner join nlp_management.dbo.Source s with (nolock) on s.id = p.sourceId
		CROSS APPLY  (
		
			SELECT productName_ngram, tipo, MIN(valor) as valor FROM #dados_produtos_relacionados			
			where
				productName_ngram <> ''
			group by
				productName_ngram, tipo

		) t2 
		where
			s.active = 1 
			and  t2.productName_ngram = p.productName_ngram


			IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('11.7: ' + CONVERT(varchar, (select COUNT(*) from #dados_produtos_relacionados_aos_relacionados)));

		
		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 2.2: productName_ngram', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
		
			SELECT @StartTime=GETDATE() 

		END


		

		-- productName_tokenizada_fingerprint
		INSERT INTO #dados_produtos_relacionados_aos_relacionados	
		select p.id, p.productName, p.productGroupId, 'productName_tokenizada_fingerprint' as tipo, p.productName_tokenizada_fingerprint as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from nlp_data_lake.dbo.CrawlerNewProductDetail p with (nolock) 
		inner join nlp_management.dbo.Source s with (nolock) on s.id = p.sourceId
		CROSS APPLY  (
		
			SELECT productName_tokenizada_fingerprint, tipo, MIN(valor) as valor FROM #dados_produtos_relacionados			
			where
					productName_tokenizada_fingerprint <> ''
			group by
				productName_tokenizada_fingerprint, tipo

		) t2 
		where
			s.active = 1 
			and  t2.productName_tokenizada_fingerprint = p.productName_tokenizada_fingerprint

			IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('11.8: ' + CONVERT(varchar, (select COUNT(*) from #dados_produtos_relacionados_aos_relacionados)));


		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 2.2: productName_tokenizada_fingerprint', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
		
			SELECT @StartTime=GETDATE() 

		END

		-- productUrl
		INSERT INTO #dados_produtos_relacionados_aos_relacionados
		select p.id, p.productName, p.productGroupId, 'productUrl' as tipo, p.productUrl as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from nlp_data_lake.dbo.CrawlerNewProductDetail p with (nolock) 
		inner join nlp_management.dbo.Source s with (nolock) on s.id = p.sourceId
		INNER JOIN #dados_produtos_relacionados t2 on t2.productUrl = p.productUrl and t2.productUrl <> ''
		where
			s.active = 1 

			IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('11.9: ' + CONVERT(varchar, (select COUNT(*) from #dados_produtos_relacionados_aos_relacionados)));


		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 2.2: productUrl', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
		
			SELECT @StartTime=GETDATE() 

		END

		-- EAN curto + Brand
		INSERT INTO #dados_produtos_relacionados_aos_relacionados
		select p.id, p.productName, p.productGroupId, 'EAN curto + Brand' as tipo, e.valor + '/' + p.feed_brand as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from nlp_data_lake.dbo.CrawlerNewProductDetail p with (nolock) 
		left join nlp_data_lake.dbo.CrawlerNewProductDetailEAN e with (nolock) on e.idCrawlerNewProductDetail = p.id
		inner join nlp_management.dbo.Source s with (nolock) on s.id = p.sourceId
		INNER JOIN #dados_produtos_relacionados t2 on t2.ean_curto <> ''  AND t2.ean_curto = e.valor AND t2.feed_brand <> '' AND t2.feed_brand = p.feed_brand and LEN(t2.feed_brand) >= 3
		where
			s.active = 1 


			IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('11.10: ' + CONVERT(varchar, (select COUNT(*) from #dados_produtos_relacionados_aos_relacionados)));

			
		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('13');

		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 2.2: EAN curto + Brand', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
		
			SELECT @StartTime=GETDATE() 

		END

		-- EAN curto + Brand tokenizada
		INSERT INTO #dados_produtos_relacionados_aos_relacionados
		select p.id, p.productName, p.productGroupId, 'EAN curto + Brand tokenizada' as tipo, e.valor + '/' + p.feed_brand_tokenizada as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from nlp_data_lake.dbo.CrawlerNewProductDetail p with (nolock) 
		left join nlp_data_lake.dbo.CrawlerNewProductDetailEAN e with (nolock) on e.idCrawlerNewProductDetail = p.id
		inner join nlp_management.dbo.Source s with (nolock) on s.id = p.sourceId
		INNER JOIN #dados_produtos_relacionados t2 on t2.ean_curto <> '' AND t2.ean_curto = e.valor AND t2.feed_brand_tokenizada <> '' AND t2.feed_brand_tokenizada = p.feed_brand_tokenizada and LEN(t2.feed_brand) >= 3
		where
			s.active = 1 

			IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('11.11: ' + CONVERT(varchar, (select COUNT(*) from #dados_produtos_relacionados_aos_relacionados)));


		 
		 IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 2.2: EAN curto + Brand tokenizada', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
		
			SELECT @StartTime=GETDATE() 

		END
		

		-- EAN curto + Brand fingerprint
		INSERT INTO #dados_produtos_relacionados_aos_relacionados
		select p.id, p.productName, p.productGroupId, 'EAN curto + Brand fingerprint' as tipo, e.valor + '/' + p.feed_brand_fingerprint as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from nlp_data_lake.dbo.CrawlerNewProductDetail p with (nolock) 
		left join nlp_data_lake.dbo.CrawlerNewProductDetailEAN e with (nolock) on e.idCrawlerNewProductDetail = p.id
		inner join nlp_management.dbo.Source s with (nolock) on s.id = p.sourceId
		INNER JOIN #dados_produtos_relacionados t2 on t2.ean_curto <> '' AND t2.ean_curto = e.valor AND t2.feed_brand_fingerprint <> '' AND t2.feed_brand_fingerprint = p.feed_brand_fingerprint and LEN(t2.feed_brand) >= 3
		where
			s.active = 1 

		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('11.12: ' + CONVERT(varchar, (select COUNT(*) from #dados_produtos_relacionados_aos_relacionados)));

		 
		 IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 2.2: EAN curto + Brand fingerprint', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
		
			SELECT @StartTime=GETDATE() 

		END
		

		-- EAN curto + Brand ngram
		INSERT INTO #dados_produtos_relacionados_aos_relacionados
		select p.id, p.productName, p.productGroupId, 'EAN curto + Brand ngram' as tipo, e.valor + '/' + p.feed_brand_ngram as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from nlp_data_lake.dbo.CrawlerNewProductDetail p with (nolock) 
		left join nlp_data_lake.dbo.CrawlerNewProductDetailEAN e with (nolock) on e.idCrawlerNewProductDetail = p.id
		inner join nlp_management.dbo.Source s with (nolock) on s.id = p.sourceId
		INNER JOIN #dados_produtos_relacionados t2 ON t2.ean_curto <> '' AND t2.ean_curto = e.valor AND t2.feed_brand_ngram <> '' AND t2.feed_brand_ngram = p.feed_brand_ngram and LEN(t2.feed_brand) >= 3
		where
			s.active = 1 

			IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('11.113 ' + CONVERT(varchar, (select COUNT(*) from #dados_produtos_relacionados_aos_relacionados)));


		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 2.2: EAN curto + Brand ngram', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
		
			SELECT @StartTime=GETDATE() 

		END
 
	IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('11.14: ' + CONVERT(varchar, (select COUNT(*) from #dados_produtos_relacionados_aos_relacionados)));


		-- productImage_hash_Imagio_ComputeHash
		INSERT INTO #dados_produtos_relacionados_aos_relacionados
		select p.id, p.productName, p.productGroupId, 'productImage_hash_Imagio_ComputeHash' as tipo, p.productImage_hash_Imagio_ComputeHash as valor, p.productPrice, productImage_downloaded,p.productImage_hash_Imagio_ComputeHash,p.productUrl,p.productName_fingerprint,p.productName_metaphone,p.productName_ngram,p.productName_tokenizada_fingerprint,p.productName_hash, t2.tipo as tipoProdutoOrigem, t2.valor as valorProdutoOrigem from nlp_data_lake.dbo.CrawlerNewProductDetail p with (nolock) 
		inner join nlp_management.dbo.Source s with (nolock) on s.id = p.sourceId
		-- INNER JOIN #dados_produtos_relacionados t2 ON t2.productImage_hash_Imagio_ComputeHash = p.productImage_hash_Imagio_ComputeHash and t2.productImage_hash_Imagio_ComputeHash <> ''
		CROSS APPLY  (
		
			SELECT productImage_hash_Imagio_ComputeHash, tipo, MIN(valor) as valor FROM #dados_produtos_relacionados			
			where
					productImage_hash_Imagio_ComputeHash <> ''
			group by
				productImage_hash_Imagio_ComputeHash, tipo

		) t2 
		where
			s.active = 1 
			and  t2.productImage_hash_Imagio_ComputeHash = p.productImage_hash_Imagio_ComputeHash
			AND p.productImage_sem_imagem_desconsiderar = 0
			
			

			IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('11.15: ' + CONVERT(varchar, (select COUNT(*) from #dados_produtos_relacionados_aos_relacionados)));

		
		IF @debug = 1
		BEGIN

			SELECT @EndTime=GETDATE()

			--This will return execution time of your query
			INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 2.2: productImage_hash_Imagio_ComputeHash', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
		
			SELECT @StartTime=GETDATE() 

		END

		
		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('14');
		-- SELECT @productName
		IF 1 = 1 BEGIN

				
		/* ---------------- Remove termos que não fazem parte do grupo (não possuem palavras semelhantes) (verificação/remoção apenas em termos que são relacionados ao EAN, pois vem muito erro dos marketplaces) ----------- */

		SELECT distinct 
			t3.id,
			t3.productName,
			t3.productName_tokenizada_fingerprint,
			t3.tipo,
			t3.valor
		INTO #idsParaDesconsiderar_depois
		FROM #dados_produtos_relacionados_aos_relacionados t3
		WHERE 
			NOT EXISTS (

				select top 1 1 from nlp.dbo.converteArrayParaTabela(productName_tokenizada_fingerprint, ' ') t1
				where exists (	
					
					select top 1 1 from #palavrasTokenizadasSeparadas t2
					 where 
						t2.palavra = t1.data
						OR t2.palavra LIKE '%' + t1.data + '%'
						OR t1.data LIKE '%' + t2.palavra + '%'
				)
				and t1.data <> ''
			)
			/*(

				select COUNT(*) from nlp.dbo.converteArrayParaTabela(productName_tokenizada_raw, ' ') t1
				where exists (	
					
					select top 1 1 from #palavrasTokenizadasSeparadas t2
					 where 
						t2.palavra = t1.data
						OR t2.palavra LIKE '%' + t1.data + '%'
						OR t1.data LIKE '%' + t2.palavra + '%'
				)
				and t1.data <> ''
			) <= 1 -- Se não tem pelo menos 2 caracteres semelhamtes, remove
			*/
			AND tipo = 'EAN longo' -- Faz a verificação/remoção apenas em termos que são relacionados ao EAN, pois vem muito erro dos marketplaces

			
		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('15');

		-- Grava Log, informando qe o agrupamento será desconsiderado
		INSERT INTO nlp_data_lake.dbo.temp_agrupamentos_ignorados (productName_origem, productName_tokenizada_origem, productName,productName_tokenizada, tipo, valor)
		SELECT @productName, @productName_tokenizada_raw,productName,productName_tokenizada_fingerprint,tipo,valor FROM #idsParaDesconsiderar_depois

		
		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('16');

		-- Desconsidera produto no agrupamento
		DELETE FROM #dados_produtos_relacionados_aos_relacionados WHERE  id in (
			SELECT id FROM #idsParaDesconsiderar_depois
		)

		
		IF @debugHard = 1 INSERT INTO temp_apagar_log (chave) VALUES ('17');
		
		DROP TABLE #idsParaDesconsiderar_depois

		/* ---------------- Remove termos que não fazem parte do grupo (não possuem palavras semelhantes) (verificação/remoção apenas em termos que são relacionados ao EAN, pois vem muito erro dos marketplaces) ----------- */


		DECLARE
			@productIdGrupo INT = 0,
			@shortName NVARCHAR(500),
			@longName NVARCHAR(500),
			@slug NVARCHAR(1500) = '',
			@posNumero_finalSlug INT,
			@numeroFinalSlug INT = 0,
			@strNumeroFinalSlug NVARCHAR(500) = ''



			-- select * from #dados_produtos_relacionados
			-- select * from #dados_produtos_relacionados_aos_relacionados


			/* ------------------------- Verifica se já existe um produto grupo pai ------------------------- */

			-- Verifica se já existe um produto pai relacionado a um dos produtos com o o item duplicado
			select TOP 1 @productIdGrupo = MIN(productGroupId) from #dados_produtos_relacionados_aos_relacionados WHERE productGroupId > 0

			-- SELECT 'Análise: Grupos relacionados que retornaram', @productId as [@productId], productGroupId, id,productName, productImage_hash_Imagio_ComputeHash, productPrice, tipo FROM #dados_produtos_relacionados ORDER BY productGroupId

			-- SELECT 'Análise: Grupos relacionados, aos relacionados que retornaram', @productId as [@productId], productGroupId, id,productName, productImage_hash_Imagio_ComputeHash, productPrice, tipo FROM #dados_produtos_relacionados_aos_relacionados ORDER BY productGroupId

	

			

			/* ------------------------- Insere um produto grupo Pai ------------------------- */

			IF ISNULL(@productIdGrupo, 0) = 0
			BEGIN

				-- SELECT 'Inseriu'
			
				-- Pega menor e maior nome do produto
				SELECT 
					*, 
					ROW_NUMBER() OVER (order by CASE WHEN productPrice > 0 THEN 1 ELSE 0 END DESC, LEN(productName) ASC) as posMenorNome,  -- Menor nome, preferencialmente com preço
					ROW_NUMBER() OVER (order by CASE WHEN productPrice > 0 THEN 1 ELSE 0 END DESC, LEN(productName) DESC) as posMaiorNome  -- Maior nome, preferencialmente com preço
				into #nomesProdutos
				FROM #dados_produtos_relacionados_aos_relacionados
				WHERE 
					productImage_hash_Imagio_ComputeHash IS NOT NULL -- Pega nome apenas de produtos com imagens


				
				SET @shortName = (SELECT productName FROM #nomesProdutos WHERE posMenorNome = 1)
				SET @longName = (SELECT productName FROM #nomesProdutos WHERE posMaiorNome = 1)
					


				/* ------------------------------------------------- Gera SLUG único ------------------------------------------------- */

				SET @slug = nlp.dbo.Slugify(@shortName)

				IF @slug IN ('lojas','marcas','categorias') 
					SET @slug = @slug + '_1'

				WHILE
				(
					(select top 1 1 from nlp_data_lake.dbo.ProductGroup with (nolock) where slug = @slug ) = 1
					OR (select top 1 1 from nlp_data_lake.dbo.ProductGroupBrand with (nolock) where slug = @slug) = 1
					OR (select top 1 1 from nlp_data_lake.dbo.ProductGroupCategory with (nolock) where slug = @slug)  = 1
					OR (select top 1 1 from nlp_management.dbo.Source with (nolock) where slug = @slug)  = 1
				)
				BEGIN

					/* ---------------- Pega número no final do Slug ---------------- */

						SET @posNumero_finalSlug = charindex('-',reverse(@slug))
					

						IF (@posNumero_finalSlug > 0)
						BEGIN

							SET @strNumeroFinalSlug  = RIGHT(@slug, @posNumero_finalSlug - 1)
	
							IF ISNUMERIC(@strNumeroFinalSlug) = 1
								SET @numeroFinalSlug = CONVERT(int, @strNumeroFinalSlug)

						END


						-- Seta novo Slug, com '_1', ou incrementando '_1', '_2', .. , '_100'
						SET @slug = CASE WHEN @numeroFinalSlug > 0 THEN
							SUBSTRING(@slug, 1, LEN(@slug) - @posNumero_finalSlug + 1) + CONVERT(varchar, @numeroFinalSlug + 1)
						ELSE
							@slug + '-1'
						END

				END


				IF (@slug = '')
					SET @slug = @shortName
				
				/* ------------------------------------------------- Gera SLUG único ------------------------------------------------- */


				-- Insere grupo
				INSERT INTO [nlp_data_lake].[dbo].[ProductGroup] (shortName, longName, slug, active)
				SELECT
					@shortName,
					@longName,
					@slug,
					(SELECT COUNT(*) FROM #dados_produtos_relacionados_aos_relacionados WHERE productImage_hash_Imagio_ComputeHash IS NOT NULL) -- O grupo só será inserido como ativo, caso tenha filhos com preço positivo, e com imagem

			
				-- SETA ID do produto Pai
				SET @productIdGrupo = SCOPE_IDENTITY()

				-- Atualiza data do 'lastPriceInserted'
				UPDATE nlp_data_lake.dbo.ProductGroup SET
					lastPriceInsertedOrProductChanged = (
						SELECT MAX(pr.lastUpdate) FROM nlp_data_lake.dbo.CrawlerNewProduct pr
						WHERE
							EXISTS (
								SELECT TOP 1 1 FROM nlp_data_lake.dbo.CrawlerNewProductDetail pd
								where
									pd.productGroupId = nlp_data_lake.dbo.ProductGroup.id
									AND pr.productUrl = pd.CrawlerNewProductProductUrl
									AND pr.sourceId = pd.sourceId
									AND pd.productImage_downloaded IS NOT NULL
									AND pd.productImage_downloaded <> ''
									AND pd.productImage_downloaded <> 'ERRO'
							)
							AND pr.productPrice > 0
					)
				WHERE
					id = @productIdGrupo

				-- Remove tabelas temporárias
				drop table #nomesProdutos
		

			END
			ELSE 
			BEGIN

				/* ------------------------- Atualiza status do grupo Pai ------------------------- */
				IF (
					-- Se o grupo pai está inativo
					SELECT COUNT(*) FROM [nlp_data_lake].[dbo].[ProductGroup] with (nolock) where id = @productIdGrupo AND active = 0 
				) > 0
				AND
				(
					-- E os filhos possuem preços e possuem imagens
					SELECT SUM(productPrice) FROM #dados_produtos_relacionados_aos_relacionados WHERE productImage_hash_Imagio_ComputeHash IS NOT NULL
					AND productGroupId = @productIdGrupo
				) > 0
				BEGIN
				
				


						-- SELECT 'Update'
			
						-- Pega menor e maior nome do produto
						SELECT 
							*, 
							ROW_NUMBER() OVER (order by CASE WHEN productPrice > 0 THEN 1 ELSE 0 END DESC, LEN(productName) ASC) as posMenorNome,  -- Menor nome, preferencialmente com preço
							ROW_NUMBER() OVER (order by CASE WHEN productPrice > 0 THEN 1 ELSE 0 END DESC, LEN(productName) DESC) as posMaiorNome  -- Maior nome, preferencialmente com preço
						into #nomesProdutos2
						FROM #dados_produtos_relacionados_aos_relacionados
						WHERE 
							productImage_hash_Imagio_ComputeHash IS NOT NULL -- Pega nome apenas de produtos com imagens
							AND productGroupId = @productIdGrupo -- Apenas do grupo atual

			
						SET @shortName = (SELECT productName FROM #nomesProdutos2 WHERE posMenorNome = 1)
						SET @longName = (SELECT productName FROM #nomesProdutos2 WHERE posMaiorNome = 1)


						/* ------------------------------------------------- Gera SLUG único ------------------------------------------------- */

						SET @slug = nlp.dbo.Slugify(@shortName)

						IF @slug IN ('lojas','marcas','categorias') 
							SET @slug = @slug + '_1'

						-- Incrementa números no final do slug, para gerar um slug único
						while (select top 1 1 from [nlp_data_lake].[dbo].[ProductGroup] with (nolock) where slug = @slug) = 1
						begin

							/* ---------------- Pega número no final do Slug ---------------- */

							SET @posNumero_finalSlug = charindex('_',reverse(@slug))


							IF (@posNumero_finalSlug > 0)
							BEGIN

								SET @strNumeroFinalSlug  = RIGHT(@slug, @posNumero_finalSlug - 1)
	
								IF ISNUMERIC(@strNumeroFinalSlug) = 1
									SET @numeroFinalSlug = CONVERT(int, @strNumeroFinalSlug)

							END


							/*
							select 
								'Tentativa',
								@slug,
								@posNumero_finalSlug as posNumero_finalSlug, 
								@numeroFinalSlug as numeroFinalSlug,
								@numeroFinalSlug + 1 as novoNumeroFinalSlug,
								CASE WHEN @numeroFinalSlug > 0 THEN
									'Demais'
								ELSE
									'Primeira'
								END as tipo_tentativa,
								CASE WHEN @numeroFinalSlug > 0 THEN
									SUBSTRING(@slug, 1, LEN(@slug) - @posNumero_finalSlug + 1) + CONVERT(varchar, @numeroFinalSlug + 1)
								ELSE
									@slug + '_1'
								END as novoSlug
							*/

							-- Seta novo Slug, com '_1', ou incrementando '_1', '_2', .. , '_100'
							SET @slug = CASE WHEN @numeroFinalSlug > 0 THEN
								SUBSTRING(@slug, 1, LEN(@slug) - @posNumero_finalSlug + 1) + CONVERT(varchar, @numeroFinalSlug + 1)
							ELSE
								@slug + '_1'
							END



						end


						IF (@slug = '')
							SET @slug = @shortName
				
						/* ------------------------------------------------- Gera SLUG único ------------------------------------------------- */

						-- Ativa o grupo, e seta nome (pois grupos inativos ficam sem o nome dos produtos)
						UPDATe [nlp_data_lake].[dbo].[ProductGroup] SET 
							active = (SELECT TOP 1 1 FROM #dados_produtos_relacionados_aos_relacionados WHERE productImage_hash_Imagio_ComputeHash IS NOT NULL AND productGroupId = @productIdGrupo), -- O grupo só será ativado, caso tenha filhos com preço positivo, e com imagem
							shortName = @shortName,
							longName = @longName,
							slug = @slug
						where id = @productIdGrupo

						-- Atualiza data do 'lastPriceInserted'
						UPDATE nlp_data_lake.dbo.ProductGroup SET
							lastPriceInsertedOrProductChanged = (
								SELECT MAX(pr.lastUpdate) FROM nlp_data_lake.dbo.CrawlerNewProduct pr
								WHERE
									EXISTS (
										SELECT TOP 1 1 FROM nlp_data_lake.dbo.CrawlerNewProductDetail pd
										where
											pd.productGroupId = nlp_data_lake.dbo.ProductGroup.id
											AND pr.productUrl = pd.CrawlerNewProductProductUrl
											AND pr.sourceId = pd.sourceId
											AND pd.productImage_downloaded IS NOT NULL
											AND pd.productImage_downloaded <> ''
											AND pd.productImage_downloaded <> 'ERRO'
									)
									AND pr.productPrice > 0
							)
						WHERE
							id = @productIdGrupo

						-- Remove tabelas temporárias
						drop table #nomesProdutos2



				END

			END



			IF @debug = 1
			BEGIN

				SELECT @EndTime=GETDATE()

				--This will return execution time of your query
				INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 4', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
		
				SELECT @StartTime=GETDATE() 

			END

			/* ------------------------- Relaciona filhos ------------------------- */

			-- Relaciona produtos filhos ao pai
			UPDATE nlp_data_lake.dbo.CrawlerNewProductDetail
			SET 
				productGroupId = @productIdGrupo,
				productGroupRelationType = B.tipo,
				productGroupRelationValue = B.valor,
				productGroupRelationTypeOriginal = B.tipoProdutoOrigem,
				productGroupRelationValueOriginal = B.valorProdutoOrigem
			FROM nlp_data_lake.dbo.CrawlerNewProductDetail A
			INNER JOIN #dados_produtos_relacionados_aos_relacionados B ON A.id = B.id
			/*
			CROSS APPLY (
				
				SELECT TOp 1 tipo, valor, tipoProdutoOrigem, valorProdutoOrigem FROM #dados_produtos_relacionados_aos_relacionados 
				WHERE 
					A.id = #dados_produtos_relacionados_aos_relacionados.id

			) as B
			*/
			WHERE
				ISNULL(A.productGroupId, 0) = 0 -- Apenas produtos ainda não relacionados



			-- Relaciona produtos filhos ao pai
			UPDATE [nlp_data_lake].dbo.[temp_flat-table_product_detail]
			SET 
				productGroupId = @productIdGrupo
			FROM [nlp_data_lake].dbo.[temp_flat-table_product_detail] A
			INNER JOIN #dados_produtos_relacionados_aos_relacionados B ON A.id = B.id	
			WHERE
				ISNULL(A.productGroupId, 0) = 0 -- Apenas produtos ainda não relacionados
		

			IF @debug = 1
			BEGIN

				SELECT @EndTime=GETDATE()

				--This will return execution time of your query
				INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 5', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
		
				SELECT @StartTime=GETDATE() 

			END


			
		
		-- SELECT COUNT(*) FROM #dados_produtos_relacionados
		-- SELECT COUNT(*) FROM #dados_produtos_relacionados_aos_relacionados
		-- SELECT @productName_metaphone, * FROM #dados_produtos_relacionados
		-- SELECT * FROM #dados_produtos_relacionados_aos_relacionados

		


		-- Remove tabelas temporárias
		drop table #palavrasTokenizadasSeparadas
		drop table #dados_produtos_relacionados
		drop table #dados_produtos_relacionados_aos_relacionados
		


	END


	/* ------------------------- Seta que houve uma tentativa de agrupamento ------------------------- */

	UPDATE nlp_data_lake.dbo.CrawlerNewProductDetail SET productRodouRotinaGroup = 1 WHERE id = @productId
	UPDATE [nlp_data_lake].dbo.[temp_flat-table_product_detail] SET productRodouRotinaGroup = 1 WHERE id = @productId

	IF @debug = 1
	BEGIN

		SELECT @EndTime=GETDATE()

		--This will return execution time of your query
		INSERT INTO #log_tempo SELECT @productId as productId, 'Bloco 6', DATEDIFF(MS,@StartTime,@EndTime) AS [Duration in millisecs]
		
		SELECT @StartTime=GETDATE() 


		END

	END
	
	
	END
	

FETCH NEXT FROM product_cursor INTO @productId, @productName, @productName_fingerprint, @productName_metaphone, @productName_ngram, @productName_tokenizada_raw, @productName_tokenizada_fingerprint,@ean_longo, @ean_curto, @productUrl, @feed_brand, @feed_brand_tokenizada, @feed_brand_ngram, @feed_brand_fingerprint, @productImage_hash_Imagio_ComputeHash

END  
  
CLOSE product_cursor  
DEALLOCATE product_cursor  


IF @debug = 1
BEGIN

	SELECT 
		tipo, 
		COUNT(*) as quant, 
		SUM(tempo) as tempo, 
		AVG(tempo) as tempo_medio
	FROM #log_tempo
	-- where tipo = 'Bloco 1: EAN LONGO'
	GROUP BY
		tipo

END


SELECT @EndTimeGeral=GETDATE()

--This will return execution time of your query
SELECT @productId as productId, 'Total', format(DATEDIFF(MS,@StartTimeGeral,@EndTimeGeral),'0,0') AS [Duration in seconds], @StartTimeGeral as StartTimeGeral, @EndTimeGeral as EndTimeGeral


drop table #log_tempo

delete from nlp_data_lake.dbo.temp_apagar_log


-- ROLLBACK


-- return

-- Inseridos
select top 10 g.id, g.longName, g.shortName, g.slug, g.active, SUM(p.productPrice) as somaPrecos, AVG(p.productPrice) as mediaPrecos, COUNT(*) as filhos from [nlp_data_lake].[dbo].[ProductGroup] g with (nolock)
inner join [nlp_data_lake].[dbo].CrawlerNewProductDetail p with (nolock)  on p.productGroupId = g.id
where
	g.id > 2399452 
GROUP BY
	g.id, g.longName, g.shortName, g.active, g.slug
ORDER BY
	g.id DESC
	-- SUM(p.productPrice) ASC


-- drop table #eansParaIgnorar
-- drop #eansParaIgnorar2



return
	
/* -------------------------------------------------------------- 5º Seta counters -------------------------------------------------------------- */


-- UPDATE nos counters de Categoria
UPDATE nlp_data_lake.dbo.ProductGroupCategory SET _quantidade = (

	SELECT 
		COUNT(*)
	FROM nlp_data_lake.dbo.ProductGroupCategory c WITH (nolock)
	INNER JOIN nlp_data_lake.dbo.ProductGroupCategoryRel rel WITH (nolock) ON rel.productGroupCategoryId = c.id
	INNER JOIN nlp_data_lake.dbo.ProductGroup g WITH (nolock) ON g.id = rel.productGroupId
	WHERE
		c.active = 1
		AND g.active = 1
		AND c.id = nlp_data_lake.dbo.ProductGroupCategory .id

)

-- UPDATE nos counters de Marca
UPDATE nlp_data_lake.dbo.ProductGroupBrand SET _quantidade = (

	SELECT 
		COUNT(*)
	FROM nlp_data_lake.dbo.ProductGroupBrand c WITH (nolock)
	INNER JOIN nlp_data_lake.dbo.ProductGroupBrandRel rel WITH (nolock) ON rel.productGroupBrandId = c.id
	INNER JOIN nlp_data_lake.dbo.ProductGroup g WITH (nolock) ON g.id = rel.productGroupId
	WHERE
		c.active = 1
		AND g.active = 1
		AND c.id = nlp_data_lake.dbo.ProductGroupBrand .id

)

/*
-- UPDATE nos counters de Site
UPDATE nlp_management.dbo.Source s with (nolock)ET _quantidadeGrupos = (

	SELECT 
		COUNT(distinct g.id)
	FROM nlp_data_lake.dbo.ProductGroup g
	INNER JOIN nlp_data_lake.dbo.CrawlerNewProductDetail pd with (nolock)  WITH (nolock) ON pd.productGroupId = g.id
	WHERE
		g.active = 1
		AND pd.sourceId = nlp_management.dbo.Source.id
		
)
*/





-- UPDATE na data de 'último produto adicionado' da Categoria
UPDATE nlp_data_lake.dbo.ProductGroupCategory SET _lastProductGroupAdded = (

	SELECT 
		MAX(pe.creationDAte)
	FROM nlp_data_lake.dbo.ProductGroupCategory c WITH (nolock)
	INNER JOIN nlp_data_lake.dbo.ProductGroupCategoryRel rel WITH (nolock) ON rel.productGroupCategoryId = c.id
	INNER JOIN nlp_data_lake.dbo.ProductGroup g WITH (nolock) ON g.id = rel.productGroupId
	INNER JOIN nlp_data_lake.dbo.CrawlerNewProductDetail pe with (nolock) on pe.productGroupId = g.id
	WHERE
		c.active = 1
		AND g.active = 1
		AND c.id = nlp_data_lake.dbo.ProductGroupCategory .id

), _firstProductGroupAdded = (

	SELECT 
		MIN(pe.creationDAte)
	FROM nlp_data_lake.dbo.ProductGroupCategory c WITH (nolock)
	INNER JOIN nlp_data_lake.dbo.ProductGroupCategoryRel rel WITH (nolock) ON rel.productGroupCategoryId = c.id
	INNER JOIN nlp_data_lake.dbo.ProductGroup g WITH (nolock) ON g.id = rel.productGroupId
	INNER JOIN nlp_data_lake.dbo.CrawlerNewProductDetail pe with (nolock)  on pe.productGroupId = g.id
	WHERE
		c.active = 1
		AND g.active = 1
		AND c.id = nlp_data_lake.dbo.ProductGroupCategory .id

)

-- UPDATE na data de 'último produto adicionado' da  Marca
UPDATE nlp_data_lake.dbo.ProductGroupBrand SET _lastProductGroupAdded = (

	SELECT 
		MAX(pe.creationDAte)
	FROM nlp_data_lake.dbo.ProductGroupBrand c WITH (nolock)
	INNER JOIN nlp_data_lake.dbo.ProductGroupBrandRel rel WITH (nolock) ON rel.productGroupBrandId = c.id
	INNER JOIN nlp_data_lake.dbo.ProductGroup g WITH (nolock) ON g.id = rel.productGroupId
	INNER JOIN nlp_data_lake.dbo.CrawlerNewProductDetail pe with (nolock)  on pe.productGroupId = g.id
	WHERE
		c.active = 1
		AND g.active = 1
		AND c.id = nlp_data_lake.dbo.ProductGroupBrand .id

), _firstProductGroupAdded = (

	SELECT 
		MIN(pe.creationDAte)
	FROM nlp_data_lake.dbo.ProductGroupBrand c WITH (nolock)
	INNER JOIN nlp_data_lake.dbo.ProductGroupBrandRel rel WITH (nolock) ON rel.productGroupBrandId = c.id
	INNER JOIN nlp_data_lake.dbo.ProductGroup g WITH (nolock) ON g.id = rel.productGroupId
	INNER JOIN nlp_data_lake.dbo.CrawlerNewProductDetail pe with (nolock)  on pe.productGroupId = g.id
	WHERE
		c.active = 1
		AND g.active = 1
		AND c.id = nlp_data_lake.dbo.ProductGroupBrand .id

)


-- UPDATE na data de 'último produto adicionado' do Site
UPDATE nlp_management.dbo.Source SET _lastProductGroupAdded = (

	SELECT 
		MAX(pd.creationDAte)
	FROM nlp_data_lake.dbo.ProductGroup g
	INNER JOIN nlp_data_lake.dbo.CrawlerNewProductDetail pd with (nolock) ON pd.productGroupId = g.id
	WHERE
		g.active = 1
		AND pd.sourceId = nlp_management.dbo.Source.id
		
), _firstProductGroupAdded = (

	SELECT 
		MIN(pd.creationDAte)
	FROM nlp_data_lake.dbo.ProductGroup g
	INNER JOIN nlp_data_lake.dbo.CrawlerNewProductDetail pd with (nolock) ON pd.productGroupId = g.id
	WHERE
		g.active = 1
		AND pd.sourceId = nlp_management.dbo.Source.id
		
)








