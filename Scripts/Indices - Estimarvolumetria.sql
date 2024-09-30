use angellira
go
declare 
	@table varchar(100) = 'dbo.posicao' --Tabela para proje��o de volumetria
	,@num_rows int = 729438980 --1 - N�mero de linhas estimadas



declare @type_sizes table ([name] varchar(50),[size] decimal(10,3),[isvariable] bit, [isstring] bit, [isprecise] bit)
insert into @type_sizes
values  ('bigint',8,0,0,0), --8 bytes
		--binary -- Tamanho do bin�rio armazenado at� 8000 bytes
		('bit',0.001,0,0,0), --1 bit
		('char',1,0,1,0), --1 byte por caracter at� 8000 bytes
		('date',3,0,0,0), --3 bytes
		('datetime',8,0,0,0), --8 bytes
		('datetime2',8,0,0,0), --6 a 8 bytes
		('datetimeoffset',10,0,0,0), --8 a 10 bytes
		('decimal',5,0,0,1), --Precis�o de 1 a 9 (5 bytes), 10 a 19 (9 bytes), 20 a 28 (13 bytes), 29 a 38 (17 bytes)
		('float',8,0,0,0), --4 ou 8 bytes
		--geography ?
		--geometry ?
		--hierchyid ?
		--image -- tamanho da im�gem armazenada at� 2GB
		('int',4,0,0,0), --4 bytes
		('money',4,0,0,0),--4 bytes
		('nchar',2,0,1,0),--2 bytes por caracter at� 4000 bytes
		('ntext',2,0,1,0),--2 bytes por caracter at� 2GB
		('numeric',5,0,0,1), --Precis�o de 1 a 9 (5 bytes), 10 a 19 (9 bytes), 20 a 28 (13 bytes), 29 a 38 (17 bytes)
		('nvarchar',2,1,1,0),--2 bytes por caracter at� 2GB
		('real',4,0,0,0),--4 bytes
		('smalldatetime',4,0,0,0),--4 bytes
		('smallint',2,0,0,0),--2 bytes
		('smallmoney',4,0,0,0),--4 bytes
		--sql_variant --tamanhos de dados vari�veis pois pode receber qualquer tipo de dados, at� 8000 bytes
		('sysname',2,0,1,0),--2 bytes por caracter at� 128 caract�res
		('text',1,0,1,0), --1 byte por caracter at� 2GB
		('time',5,0,0,0), --3 a 5 bytes
		('timestamp',8,0,0,0), --8 bytes
		('tinyint',1,0,0,0), --1 byte
		('uniqueidentifier',16,0,0,0), --8 byte
		--varbinary -- bin�rios de tamanhos vari�veis at� 8000 bytes
		('varchar',1,1,1,0)--1 bytes por caracter at� 2GB
		--xml at� 2GB

declare 
	@num_cols bigint
	,@fixed_data_size decimal(10,3)
	,@num_variable_cols bigint
	,@max_var_size bigint
	,@null_bitmap bigint
	,@variable_data_size bigint = 0
	,@rows_per_page bigint
	,@num_pages bigint
	,@heap_size bigint
	,@row_size bigint


select 
	@num_cols = count(1), --2.1 n�mero de colunas da tabela
	@fixed_data_size = sum(case  
								when ts.isvariable = 0 and ts.isstring = 1 then ts.size * cl.max_length
								when ts.isvariable = 0 and ts.isprecise = 1 then ts.size + ((cl.[precision] / 10)*4)--Precis�o de 1 a 9 (5 bytes), 10 a 19 (9 bytes), 20 a 28 (13 bytes), 29 a 38 (17 bytes)
								when ts.isvariable = 0 and ts.isstring = 0 then ts.size 
							end), --2.2 Tamanho em bytes das colunas de custo fixo
	@num_variable_cols = count(case ts.isvariable when 1 then 1 end), --2.3 N�mero de colunas de tipos vari�veis
	@max_var_size = sum(case ts.isvariable when 1 then ts.size * cl.max_length else 0 end) --2.4 numero de colunas com tipos vari�veis, levando em considera��o que estejam completamente preenchidas
from sys.columns cl
	join sys.types tp 
		on cl.system_type_id = tp.system_type_id
	join @type_sizes ts
		on tp.[name] = ts.[name]
where 
	cl.[object_id] = object_id(@table)
option(recompile)
--------------------------------------------------------------------------------------------------------------------------------------------------------
--Calcular tamanho heap
--------------------------------------------------------------------------------------------------------------------------------------------------------

--3 Null_Bitmap - parte da linha reservada para gerenciar a nulabilidade da coluna, considera-se apenas o n�mero inteiro do calulo, descartando o restante.
select @null_bitmap = 2 + ((@num_cols + 7) / 8)

--4 Tamanho dos dados de comprimento vari�vel
if @num_variable_cols > 0
	select @variable_data_size = 2 + (@num_variable_cols * 2) + @max_var_size

--5 Calculo do tamanho total da linha, o valor 4 na formula � a sobrecarga do cabe�alho da linha de dados
select @row_size = @fixed_data_size + @variable_data_size + @null_bitmap + 4

--6 Calculo do n�mero de linhas por p�gina, o valor 2 na f�rmula � para a entrada da linha na matriz de slot da pagina
select @rows_per_page = floor(8096.0 / (@row_size + 2))

--7 Calcular o n�mero de p�ginas necess�rio para armazenar todas as linhas, deve ser arredondado pra cima at� a proxima p�gina inteira mais pr�xima
select  @num_pages = ceiling(@num_rows / cast(@rows_per_page as decimal))

--8 Calcular tamanho do heap em bytes
select @heap_size = (8192 * @num_pages)

--------------------------------------------------------------------------------------------------------------------------------------------------------
--Calcular tamanho �ndice Clustered
--------------------------------------------------------------------------------------------------------------------------------------------------------

declare 
	@clustered_index bit = 0
	,@unique_index bit = 0
	,@fill_factor bigint
	,@free_rows_per_page bigint 
	,@num_leaf_pages bigint
	,@leaf_space_used bigint
	,@num_key_cols bigint
	,@fixed_key_size bigint
	,@num_variable_key_cols bigint
	,@max_var_key_size bigint
	,@null_key_columns bigint
	,@index_null_bitmap bigint = 0
	,@variable_key_size bigint = 0
	,@index_row_size bigint
	,@index_rows_per_page bigint
	,@non_leaf_levels bigint
	,@index_level bigint = 1
	,@num_index_pages bigint = 0
	,@index_space_used bigint
	,@clustered_index_size bigint

select 
	@clustered_index = 1
	,@unique_index = is_unique
	,@fill_factor = case fill_factor when 0 then 100 else fill_factor end 
from sys.indexes 
where [object_id] = object_id(@table)
	and index_id = 1

if @clustered_index = 1
begin
	select 
		@num_key_cols = count(1), --2.1 n�mero de colunas na chave do indice
		@fixed_key_size = sum(case  
									when ts.isvariable = 0 and ts.isstring = 1 then ts.size * cl.max_length
									when ts.isvariable = 0 and ts.isprecise = 1 then ts.size + ((cl.[precision] / 10)*4)--Precis�o de 1 a 9 (5 bytes), 10 a 19 (9 bytes), 20 a 28 (13 bytes), 29 a 38 (17 bytes)
									when ts.isvariable = 0 and ts.isstring = 0 then ts.size 
								end), --2.2 Tamanho em bytes das colunas de custo fixo
		@num_variable_key_cols = count(case ts.isvariable when 1 then 1 end), --2.3 N�mero de colunas de tipos vari�veis
		@max_var_key_size = sum(case ts.isvariable when 1 then ts.size * cl.max_length else 0 end), --2.4 numero de colunas com tipos vari�veis, levando em considera��o que estejam completamente preenchidas
		@null_key_columns = sum(cast(cl.is_nullable as int)) 
	from sys.columns cl
		join sys.types tp 
			on cl.system_type_id = tp.system_type_id
		join @type_sizes ts
			on tp.[name] = ts.[name]
		join sys.index_columns ic
			on cl.[object_id] = ic.[object_id]
				and cl.column_id = ic.column_id
					and ic.index_id = 1
	where 
		cl.[object_id] = object_id(@table)
	option(recompile)

	if @unique_index = 0 --Caso a chave do �ndice clustered n�o seja unique, cria-se uma nova coluna vari�vel de 4 bytes que funcionar� como identificador de exclusividade, ent�o o tamanho da linha dever� ser recalculado, assim como as colunas que fazem parte dos n�veis superiores do �ndice.
		begin
			select 
				@num_cols += 1,
				@num_variable_cols +=1,
				@max_var_size += 4,
				@num_key_cols += 1,
				@num_variable_key_cols+=1,
				@max_var_key_size+=4


				
			select
				@variable_data_size = 2 + (@num_variable_cols * 2) + @max_var_size,
				@null_bitmap = 2 + ((@num_cols + 7) / 8),
				@row_size = @fixed_data_size + @variable_data_size + @null_bitmap + 4,
				@rows_per_page = floor(8096.0 / (@row_size + 2))
		end 

	--8 Calcular o n�mero de linhas livres reservadas por p�ginas
	select @free_rows_per_page = floor(8096.0 * ((100 - @fill_factor) / 100) / (@row_size + 2))

	--9 Calcular o n�mero de p�ginas necess�rias para armazenar todas as linhas
	select @num_leaf_pages = ceiling(cast(@num_rows as decimal) / (@rows_per_page - @free_rows_per_page))

	--10 Calcular a quantidade de espa�o necess�ria para armazenar os dados do n�vel folha em bytes
	select @leaf_space_used = 8192 * @num_leaf_pages

	------------------------------------------------------------------------------------------------------
	--Calcular n�veis superiores do �ndice
	------------------------------------------------------------------------------------------------------

	--11 Calcular null bitmap
	if @null_key_columns > 0
		select @index_null_bitmap = 2 + ((@num_key_cols + 7)/8)
	
	--12 Calcular o tamanho dos dados de comprimento vari�vel
	if @num_variable_cols > 0
		select @variable_key_size = 2 + (@num_variable_key_cols * 2) + @max_var_key_size

	--13 Calcular o tamanho da linha de �ndice
	select @index_row_size = @fixed_key_size + @variable_key_size + @index_null_bitmap + 1 + 6
	-- +1 Sobrecarga de cabe�alho de linha de uma linha de �ndice +6 para ponteiro de ID da p�gina filho

	--14 Calcular o n�mero de linhas de �ndice por p�gina (8.096 bytes livres por p�gina)
	select @index_rows_per_page = floor(8096.0 / (@index_row_size + 2)) 
	-- +2 Para a entrada da linha na matriz de slots da p�gina

	--15 Calcular o n�mero de n�veis no �ndice
	select @non_leaf_levels = ceiling(1 + log((cast(@num_leaf_pages as float) / @index_rows_per_page),@index_rows_per_page))

	--16 Calcular o n�mero de p�ginas n�o folha no �ndice
	while (@index_level <= @non_leaf_levels)
	begin
		select @num_index_pages += ceiling(cast(@num_leaf_pages as float) / power(@index_rows_per_page,cast(@index_level as float)))
		set @index_level += 1
	end

	--17 Calcule o tamanho do �ndice (total de 8.912 bytes por p�gina)
	select @index_space_used = 8192 * @num_index_pages

	--18 Tamanho do �ndice clusterizado (bytes)
	select @clustered_index_size = @leaf_space_used + @index_space_used


end






select @heap_size [@heap_size bytes], @clustered_index_size /1024 /1024 [@clustered_index_size]

select
	@free_rows_per_page [@free_rows_per_page]
	,@num_leaf_pages [@num_leaf_pages]
	,@index_rows_per_page [@index_rows_per_page] 
	,@leaf_space_used [@leaf_space_used]
	,@num_index_pages [@num_index_pages]

