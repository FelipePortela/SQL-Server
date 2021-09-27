USE [DBA]
GO

/****** Object:  StoredProcedure [dbo].[sp_backuprds]    Script Date: 27/09/2021 11:10:56 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE procedure [dbo].[sp_backuprds]
(
	@database varchar(250) = null
	,@bucket varchar(1000) 
	,@type nvarchar(100) 
)
as
begin

	declare @min int = 1
			,@max int
			,@s3_arn_to_backup_to nvarchar(4000)
			,@lifecycle varchar(100)
	

	drop table if exists #databases_backup
	select
		row_number() over (order by database_id) [rowid]
		,[name]
	into #databases_backup
	from sys.databases 
	where database_id > 4 
		and [name] <> 'rdsadmin'
		and [name] = isnull(@database, [name])
	set @max = @@rowcount

	while @min <= @max
	begin
	
		select
			@database = [name]
		from #databases_backup
		where [rowid] = @min

		select @s3_arn_to_backup_to = 'arn:aws:'+replace(@bucket,'s3://','s3:::')+@database+'_backup_'+lower(@type)+'_'+convert(varchar,getdate(),112)+'_'+replace(convert(varchar,getdate(),108),':','')+'.bak'


		exec msdb.dbo.rds_backup_database 
			@source_db_name=@database, 
			@s3_arn_to_backup_to=@s3_arn_to_backup_to,
			@overwrite_S3_backup_file=1;

		drop table if exists #rds_task_status;
		create table #rds_task_status
		(
			task_id int,
			task_type varchar(max),
			[database_name] varchar(max),
			[percent_complete] int,
			[Duration_min] int,
			lifecycle varchar(max),
			task_info varchar(max),
			last_updated datetime,
			created_at datetime,
			sw_object_arn varchar(max),
			overwrite_s3_backup_file bit,
			kms_nmaster_key_arn varchar(max),
			filepath varchar(max),
			overwrite_file bit
		)

		insert into #rds_task_status
		exec msdb.dbo.rds_task_status;


		select 
			top 1 @lifecycle = lifecycle
		from #rds_task_status
		where [database_name] = @database
			and task_type = 'BACKUP_DB'
		order by task_id desc
	
		select @database, @lifecycle

		if @lifecycle = 'ERROR'
			RAISERROR ('Erro na rotina de backup, favor verificar usando a procedure exec msdb.dbo.rds_task_status', 16, 1); 
		else if @lifecycle <> 'SUCCESS'
			waitfor delay '00:01:00'


		set @min += 1
	end

end



GO


