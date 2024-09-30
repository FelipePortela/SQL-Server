use dba
go

if object_id('fn_split') is not null
	drop function fn_split
go

create function [dbo].[fn_split]
(
    @string varchar(5000),
    @delimiter char(1)
)
returns table
as
return
(
    with split(stpos,endpos)
    as(
        select 0 as stpos, charindex(@delimiter,@string) as endpos
        union all
        select endpos+1, charindex(@delimiter,@string,endpos+1)
            from split
            where endpos > 0
    )
    select 'data' = rtrim(ltrim(substring(@string,stpos,coalesce(nullif(endpos,0),len(@string)+1)-stpos)))
    from split
)

go

set nocount on

declare
	@db_rebuild varchar(500) 
	,@db_except varchar(500)
	,@maxdop tinyint = 0 
	,@rebuild_table bit = 1
	,@rebuild_offline bit = 0
	,@auto_compress varchar(10) = null
	,@compression_threshold_mb int = 500
	,@min_fragmentation tinyint = 10
	,@max_fragmentation tinyint = 20
	,@min_index_pages int = 1000
	,@low_fragmentation_action varchar(100) = 'reorganize'
	,@high_fragmentation_action varchar(100) = 'rebuild'
	,@partitioned_offline bit = 0
	,@lock_timeout_min tinyint = 1
	,@lock_kill_action varchar(10)= 'SELF'
	,@log_rebuild_to_table bit = 1
	,@disk_free_space_threshold_mb int = 25000
	,@disk_free_space_threshold_percent int = 20

	
declare 
	@mindb int = 1
	,@minind int = 1
	,@maxdb int
	,@maxind int
	,@rebuild bit
	,@partitioned bit
	,@indexsize int
	,@index_id int
	,@index_name varchar(150)
	,@partition_number int
	,@schema_name varchar(150)
	,@object_name varchar(150)
	,@text_ntext_image bit
	,@database varchar(100)
	,@server_edition varchar(30)
	,@product_version varchar(30)
	,@cmd nvarchar(max)
	,@cmd_aux nvarchar(max)
	,@tempdb_disk varchar(50)
	,@tempdb_disk_space int
	,@tempdb_disk_space_percent int
	,@last_collection datetime
	,@datafile_freespace int
	,@data_disk_freespace_percent int
	,@log_disk_freespace_percent int
	,@logfile_freespace int
	,@sort_in_tempdb bit = 0
	,@online bit
	,@exec_check bit = 1
	,@exec_message varchar(8000)
	,@exec_compression bit = 0
	,@current_Compression varchar(10)
	,@data_space_id int

set @server_edition = cast(serverproperty('Edition') as varchar)
set @product_version = cast(serverproperty('productversion') as varchar)


if object_id('tempdb..#databases_rebuild') is not null
	drop table #databases_rebuild

if @log_rebuild_to_table = 1
begin 
	if object_id('dba_hist.dbo.rebuild_log') is null
	begin
		create table dba_hist.dbo.rebuild_log
		(
			[timestamp] datetime,
			[Operacao] varchar(100),
			[Status] bit,
			[Mensagem] varchar(8000)
		)		
		create clustered index idx_rebuild_log_timestamp on dba_hist.dbo.rebuild_log([timestamp]) with (data_compression=page)
	end
	else
		truncate table dba_hist.dbo.rebuild_log
end

if object_id('dba_hist.dbo.fragmentation_baseline') is null
begin
	create table [dba_hist].[dbo].[fragmentation_baseline](
		[timestamp] [datetime],
		[database] [nvarchar](128) null,
		[schema] [nvarchar](128) null,
		[table] [sysname] not null,
		[index] [sysname] null,
		[index_id] [int] null,
		[data_space_id] [int] null,
		[partition_number] [int] null,
		[user_seeks] [bigint] null,
		[user_scans] [bigint] null,
		[user_lookups] [bigint] null,
		[user_updates] [bigint] null,
		[last_user_read] [datetime] null,
		[last_user_update] [datetime] null,
		[avg_fragmentation_in_percent] [float] null,
		[page_count] [bigint] null,
		[text_ntext_image] [bit] null
	) on [primary]
	create clustered index idx_fragmentation_baseline_database_timestamp on [dba_hist].[dbo].fragmentation_baseline([database],[timestamp] desc) with (data_compression = page)
end

select
	row_number() over (order by database_id) [dbid]
	,[name]
into #databases_rebuild
from sys.databases db
where [state] = 0
	and [database_id] > 4
	and ( @db_rebuild is null or exists(select 1 from dbo.fn_split(@db_rebuild,',') fn where db.[name] = fn.[data]))
	and not exists(select 1 from dbo.fn_split(@db_except,',') fn where db.[name] = fn.[data])
set @maxdb = @@rowcount
	
while (@mindb <= @maxdb)
begin
	
	select 
		@database = [name]
	from #databases_rebuild
	where [dbid] = @mindb

	if @log_rebuild_to_table = 1 
		insert into dba_hist.dbo.rebuild_log values (getdate(),null,0,'Iniciando manutenção dos índices no banco: '+@database)
	else
		print 'Iniciando manutenção dos índices no banco: '+@database
	
	select top 1 @last_collection = [timestamp] from [dba_hist].[dbo].[fragmentation_baseline] where [database] = @database
	
	if ((datediff(hour,@last_collection,getdate()) > 48) or @last_collection is null) 
	begin
		set @cmd =
		'
		use ['+@database+'];

		;with text_fields as
		(
			select distinct
				c.[object_id]
				,isnull(ic.index_id,(select min(index_id) from sys.indexes i where i.object_id = c.object_id)) [index_id]
				,1 [text_ntext_image]
			from sys.columns c 
				join sys.types t
					on c.system_type_id = t.system_type_id
				left join sys.index_columns ic
					on c.[object_id] = ic.[object_id]
						and c.column_id = ic.column_id
			where t.[name] in (''text'', ''ntext'', ''image'')
		)
		select
			getdate() [timestamp],
			db_name() [database],
			schema_name(obj.schema_id) [schema],
			obj.[name] [table],
			iif(i.index_id = 0,''heap'',i.[name]) [index],
			i.index_id,
			au.data_space_id,
			ips.partition_number,
			isnull(ius.user_seeks,0) user_seeks,
			isnull(ius.user_scans,0) user_scans,
			isnull(ius.user_lookups,0) user_lookups,
			isnull(ius.user_updates,0) user_updates,
			(select max([read]) from (values (last_user_scan), (last_user_seek)) as value([read]) ) last_user_read,
			ius.last_user_update,
			max(ips.avg_fragmentation_in_percent),
			max(ips.page_count),
			isnull(tf.[text_ntext_image],0) [text_ntext_image]
		from sys.objects obj
			join sys.indexes i
				on obj.object_id = i.object_id
			left join sys.dm_db_index_usage_stats ius
				on i.object_id = ius.object_id	
					and i.index_id = ius.index_id
			inner join sys.dm_db_index_physical_stats(db_id(),null,null,null,''limited'') ips
				on i.object_id = ips.object_id
					and i.index_id = ips.index_id
			inner join sys.allocation_units au
				on ips.hobt_id = au.container_id
		    left join text_fields tf
				on i.object_id = tf.object_id
					and i.index_id = tf.index_id
		where obj.[type] in (''U'',''V'')
			'+iif(@rebuild_table = 0, 'and i.index_id > 0','')+'
			and avg_fragmentation_in_percent > '+cast(@min_fragmentation as varchar)+'
			and page_count > '+cast(@min_index_pages as varchar)+'
		group by 
			obj.[schema_id]
			,obj.[name]
			,i.index_id
			,i.[name]
			,au.data_space_id
			,ips.partition_number
			,ius.user_seeks
			,ius.user_scans
			,ius.user_lookups
			,ius.user_updates
			,ius.last_user_scan
			,ius.last_user_seek
			,ius.last_user_update
			,tf.[text_ntext_image]

		'
		insert into [dba_hist].[dbo].[fragmentation_baseline] exec sp_executesql @cmd
		select top 1 @last_collection = [timestamp] from [dba_hist].[dbo].[fragmentation_baseline] where [database] = @database
	end

	if object_id('tempdb..#rebuild_cmd') is not null
		drop table #rebuild_cmd
			
	select 
	row_number() over (order by  [schema],[table],index_id ) [rowid]
	,[schema]
	,[table]
	,index_id
	,[index]
	,partition_number
	,data_space_id
	,case 
		when index_id > 0 and avg_fragmentation_in_percent < @max_fragmentation and @low_fragmentation_action = 'rebuild' then 1
		when index_id > 0 and avg_fragmentation_in_percent >= @max_fragmentation and @high_fragmentation_action = 'rebuild' then 1
		else 0
	end [rebuild]
	,[text_ntext_image]
	,page_count / 128 [index_size_MB]
	,case when (max(partition_number) over (partition by [schema],[table],[index]) > 1) then 1 else 0 end [partitioned]
	,'alter '+iif(index_id = 0,'table', 'index ['+[index]+'] on ')+'['+[database]+'].['+[schema]+'].['+[table]+'] '
	+case 
		when index_id = 0 and @rebuild_table = 1 then ' rebuild'
		when avg_fragmentation_in_percent < @max_fragmentation then @low_fragmentation_action
		else @high_fragmentation_action
		end
	+case when (max(partition_number) over (partition by [schema],[table],[index]) > 1 and cast(left(@product_version,2) as int) > 12)
				or (max(partition_number) over (partition by [schema],[table],[index]) > 1 and @partitioned_offline = 1)
		then ' partition = '+cast(partition_number as varchar)
		else ''
	end [command]
	into #rebuild_cmd
	from [dba_hist].[dbo].[fragmentation_baseline] 
	where [database] = @database
	and [timestamp] = @last_collection


	set @maxind = @@rowcount

	select @database, @maxind

	create clustered index idx_temp_rebuild_cmd_rowid on #rebuild_cmd([rowid])

	while (@minind <= @maxind)
	begin
		select
			@rebuild = [rebuild]
			,@schema_name = [schema]
			,@object_name = [table]
			,@index_id = [index_id]
			,@data_space_id = [data_space_id]
			,@partition_number = [partition_number]
			,@index_name = [index]
			,@partitioned = [partitioned]
			,@text_ntext_image = [text_ntext_image]
			,@cmd = [command]
			,@indexsize = [index_size_MB] + @disk_free_space_threshold_mb
		from #rebuild_cmd 
		where [rowid] = @minind


		print 'Executando processo para o índice ['+@database+'].['+@schema_name+'].['+@object_name+'].['+@index_name+']'

		if object_id('tempdb..#disks') is not null
		drop table #disks

		create table #disks 
		(
			[disk] varchar(10)
			,[type_desc] varchar(10)
			,livreMB int
			,Espaco_disco_percent int
		)
		
		set @cmd_aux = '
			use ['+@database+']; 
	
			select 
				volume_mount_point,
				type_desc, 
				sum(((size - fileproperty([name],''spaceused''))/128) + (dvs.available_bytes /1024 /1024))  [livreMB],
				min(cast(((available_bytes / 1048576.0) / (total_bytes / 1048576.0))*100 as int)) [Espaco_disco_percent]
				from sys.database_files 
					cross apply sys.dm_os_volume_stats(db_id(), file_id) dvs
				where [type] = 1 or ([type] = 0 and data_space_id = '+cast(@data_space_id as varchar)+')
				group by volume_mount_point,
				data_space_id,
				type_desc '
		
		insert into #disks
		exec(@cmd_aux)

		select 
			@datafile_freespace = sum(case when [type_desc] = 'ROWS' then [livreMB] end)
			,@data_disk_freespace_percent = min(case when [type_desc] = 'ROWS' then [Espaco_disco_percent] end)
			,@logfile_freespace = sum(case when [type_desc] = 'LOG' then [livreMB] end)
			,@log_disk_freespace_percent = min(case when [type_desc] = 'log' then [Espaco_disco_percent] end)
		from #disks
		
		exec sp_executesql N'use tempdb;
							select 
								@temp_utilizado = sum((size - fileproperty([name],''spaceused''))/128)
							from sys.database_files df where type = 0
						',N'@temp_utilizado int output', @temp_utilizado = @tempdb_disk_space output

		select 
			@tempdb_disk = volume_mount_point 
			,@tempdb_disk_space = @tempdb_disk_space + available_bytes / 1024 /1024
			,@tempdb_disk_space_percent = cast(((available_bytes / 1048576.0) / (total_bytes / 1048576.0))*100 as int)
		from sys.dm_os_volume_stats(2, 1)

		if not exists (select 1 from #disks where [disk] = @tempdb_disk) 
			and @tempdb_disk_space > @indexsize 
			and (	@tempdb_disk_space_percent > @disk_free_space_threshold_percent 
					or @tempdb_disk_space > @disk_free_space_threshold_mb
				)
		begin
			set @sort_in_tempdb = 1
		end
		
		select @online = case
							when @text_ntext_image = 1 then 0
							when @server_edition not like '%enterprise%' and @server_edition not like '%developer%' then 0
							when @partitioned = 1 and cast(left(@product_version,2) as int) < 13 then 0
							else 1
						end

		if @auto_compress is not null
		begin
			begin try
				set @cmd_aux = 'use ['+@database+'];
							
					select 
							@compression = data_compression_desc
					from sys.partitions 
					where object_id = object_id('''+@schema_name+'.'+@object_name+''')
						and index_id = '+cast(@index_id as varchar)+'
							and partition_number = '+cast(@partition_number as varchar)+'
					'
				exec sp_executesql @cmd_aux,N'@compression varchar(10) output', @compression = @current_Compression output
			
				if @current_Compression <> upper(@auto_compress)
				begin		
					if object_id('tempdb..#estimate_compression') is not null
						drop table #estimate_compression

					create table #estimate_compression
					(
						[object_name] sysname
						,[schema_name] sysname
						,[index_id] int
						,[partition_number] int
						,[size_with_current_compression_setting_KB] bigint
						,[size_with_requested_compression_setting_KB] bigint
						,[sample_size_with_current_compression_setting_KB] bigint
						,[sample_size_with_requested_compression_setting_KB] bigint
					)

					set @cmd_aux = '
									use ['+@database+'];
									exec sp_estimate_data_compression_savings	@schema_name = '''+@schema_name+''',  
																				@object_name = '''+@object_name+''', 
																				@index_id = '+cast(@index_id as varchar)+', 
																				@partition_number = '+cast(@partition_number as varchar)+', 
																				@data_compression = '''+@auto_compress+'''
								   '
						insert into #estimate_compression
						exec sp_executesql @cmd_aux

					if ((select ([size_with_current_compression_setting_KB] - [size_with_requested_compression_setting_KB])/1024 from #estimate_compression) >= @compression_threshold_mb)
						set @exec_compression = 1
				end
				
			end try
			begin catch
				set @exec_compression = 0
					
				if @log_rebuild_to_table = 1 
					insert into dba_hist.dbo.rebuild_log values (getdate(),'Estimar compressão',1,'Erro :'+error_message()+' ao estimar compressão do índice: ['+@database+'].['+@schema_name+'].['+@object_name+'].['+@index_name+']')
				else
					print 'Erro :'+error_message()+' ao estimar compressão do índice: ['+@database+'].['+@schema_name+'].['+@object_name+'].['+@index_name+']'
			end catch
			
		end
		

		select
			@cmd = @cmd + case when @rebuild = 0 
						then ''
						else ' with ( ONLINE = '+ case @online when 1 
																then 'ON '+iif(@lock_timeout_min > 0, ' (WAIT_AT_LOW_PRIORITY (MAX_DURATION = '+cast(@lock_timeout_min as varchar)+' MINUTES, ABORT_AFTER_WAIT = '+@lock_kill_action+')) ','') 
																else 'OFF'
													end
												+case when @maxdop > 0 then ', MAXDOP = '+cast(@maxdop as varchar)
													else ''
												 end
												+case when @exec_compression = 1 then ', DATA_COMPRESSION = '+@auto_compress
													else ''
												end
												+ case when @sort_in_tempdb = 1 and @index_id > 1 then ', SORT_IN_TEMPDB = ON '
														else ''
												end+' )'
												
						end 		
		
		if (@rebuild = 1 and @online = 0 and @rebuild_offline = 0)
			begin
				select @exec_check = 0, 
						@exec_message = 'Não foi possível fazer o rebuild do índice ['+
						@database+'].['+@schema_name+'].['+@object_name+'].['+
						@index_name+'] online, favor agendar a execução assistida do comando "'+
						@cmd+'", ou executar a procedure permitindo rebuild offline @rebuild_offline = 1'
			end
		--Valida espaço nos datafiles
		if (	@rebuild = 1 
				and @sort_in_tempdb = 0 
				and @online = 1 
				and (	@indexsize > @datafile_freespace 
						or @datafile_freespace < @disk_free_space_threshold_mb 
						or (@data_disk_freespace_percent < @disk_free_space_threshold_percent and @datafile_freespace < @disk_free_space_threshold_mb)
					)
			)
		begin
			select @exec_check = 0, 
					@exec_message =  'Não foi possível fazer o rebuild do índice ['+
					@database+'].['+@schema_name+'].['+@object_name+'].['+@index_name+'] '+
					case when @indexsize > @datafile_freespace 
							then 'por falta de espaço no arquivo de dados, espaço necessário: '
								+cast(@indexsize as varchar)+'MB espaço disponível: '+cast(@datafile_freespace as varchar)+'MB'
							when @datafile_freespace < @disk_free_space_threshold_mb 
							then 'o disco onde está o arquivo de dados possui '+cast(@disk_free_space_threshold_mb as varchar)+'MB livres'

							when @data_disk_freespace_percent < @disk_free_space_threshold_percent and @datafile_freespace < @disk_free_space_threshold_mb
							then 'o disco onde do arquvo de dados está '+cast(100 - @log_disk_freespace_percent as varchar)+' utilizado'
					end+'comando:"'+@cmd+'"'
		end
		--Valida espaço no transaction log
		if (	@rebuild = 1 
				and (	@indexsize > @logfile_freespace 
						or @logfile_freespace < @disk_free_space_threshold_mb 
						or (@log_disk_freespace_percent < @disk_free_space_threshold_percent and @logfile_freespace < @disk_free_space_threshold_mb)
					)
			)
		begin
			select @exec_check = 0, 
					@exec_message =  'Não foi possível fazer o rebuild do índice ['+
					@database+'].['+@schema_name+'].['+@object_name+'].['+@index_name+'] '+
					case when @indexsize > @logfile_freespace 
							then 'por falta de espaço no transaction log, espaço necessário: '
								+cast(@indexsize as varchar)+'MB espaço disponível: '+cast(@datafile_freespace as varchar)+'MB'
							when @logfile_freespace < @disk_free_space_threshold_mb 
							then 'o disco onde está o transaction log possui '+cast(@disk_free_space_threshold_mb as varchar)+'MB livres'

							when @log_disk_freespace_percent < @disk_free_space_threshold_percent and @logfile_freespace < @disk_free_space_threshold_mb
							then 'o disco onde doo transaction log está '+cast(100 - @log_disk_freespace_percent as varchar)+' utilizado'
					end+'comando:"'+@cmd+'"'

		end

		if @exec_check = 1
		begin
			begin try
				exec sp_executesql @cmd
				
				if @log_rebuild_to_table = 1 
					insert into dba_hist.dbo.rebuild_log values (getdate(),'Execucão rebuild',0,'Manutenção do índice ['+@database+'].['+@schema_name+'].['+@object_name+'].['+@index_name+'] executada com sucesso')
				else
					print 'Manutenção do índice ['+@database+'].['+@schema_name+'].['+@object_name+'].['+@index_name+'] executada com sucesso'

			end try
			begin catch
				if @log_rebuild_to_table = 1 
					insert into dba_hist.dbo.rebuild_log values (getdate(),'Execucão rebuild',1,'Erro :'+error_message()+' ao executar o comando: "'+@cmd+'"')
				else
					print 'Erro :'+error_message()+' ao executar o comando: "'+@cmd+'"'
			end catch
		end
		else
		begin
			if @log_rebuild_to_table = 1 
				insert into dba_hist.dbo.rebuild_log values (getdate(),'Execucão rebuild',1,@exec_message)
			else
				print @exec_message
		end 

		set @minind = @minind + 1
		
	end

	if @log_rebuild_to_table = 1 
		insert into dba_hist.dbo.rebuild_log values (getdate(),null,0,'Manutenção dos índices finalizada no banco de dados '+@database)
	else
		print 'Manutenção dos índices finalizada no banco de dados '+@database

	set @minind = 1
	set @mindb = @mindb + 1
end