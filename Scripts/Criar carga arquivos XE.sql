USE [DBA_HIST]
GO

/****** Object:  Table [dbo].[xe_tsql_monitor]    Script Date: 23/06/2021 11:48:02 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

drop table if exists xe_tsql_monitor;

CREATE TABLE [dbo].[xe_tsql_monitor](
	[TimeStamp] [datetime] NULL,
	[Event_type] [nvarchar](60) NOT NULL,
	[Server] [varchar](100) NULL,
	[Username] [varchar](100) NULL,
	[Host] [varchar](100) NULL,
	[Database] [varchar](100) NULL,
	[query_hash] [varchar](50) NULL,
	[Logical_reads] [bigint] NULL,
	[Physical_reads] [bigint] NULL,
	[Writes] [bigint] NULL,
	[Cpu_time] [bigint] NULL,
	[Duration] [bigint] NULL,
	[object_name] [varchar](100) NULL,
	[Query] [varchar](max) NULL,
	[Statement] [varchar](max) NULL,
	[Error_number] [int] NULL,
	[Error_category] [varchar](100) NULL,
	[Error_Message] [varchar](2000) NULL,
	[file_name] [nvarchar](260) NOT NULL,
	[file_offset] [bigint] NOT NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
create clustered index idx_xe_tsqlmonitor_timestamp on xe_tsql_monitor([timestamp]) with (data_compression = page)

go

drop procedure if exists dbo.sp_xe_tsqlcollect
go

create procedure dbo.sp_xe_tsqlcollect
as
begin

	declare @file nvarchar(260), @offset bigint, @path varchar(100) = (select top 1 left(log_file_path,2)+'\XE\*.xel' from sys.server_file_audits)

	select top 1
		@file = [file_name]
		,@offset = file_offset
	from dba_hist.dbo.xe_tsql_monitor
	order by [timestamp] desc
	

	drop table if exists #extendedevents;
	select 
		[file_name]
		,file_offset
		,[object_name]
		,cast(event_data as xml) Event_data 
	into #extendedevents  
	from sys.fn_xe_file_target_read_file( @path,null,@file,@offset)

	insert into dba_hist.dbo.xe_tsql_monitor
	select
			dateadd(hour,(-3),event_data.value(N'(event/@timestamp)[1]',N'datetime')) [TimeStamp]
			,[object_name] [Event_type]
			,event_data.value(N'(event/action[@name="server_instance_name"]/value)[1]',N'varchar(100)') [Server]
			,event_data.value(N'(event/action[@name="username"]/value)[1]',N'varchar(100)') [Username]
			,event_data.value(N'(event/action[@name="client_hostname"]/value)[1]',N'varchar(100)') [Host]
			,event_data.value(N'(event/action[@name="database_name"]/value)[1]',N'varchar(100)') [Database]
			,event_data.value(N'(event/action[@name="query_hash"]/value)[1]',N'varchar(50)') [query_hash]
			,event_data.value(N'(event/data[@name="logical_reads"]/value)[1]',N'bigint') [Logical_reads]
			,event_data.value(N'(event/data[@name="physical_reads"]/value)[1]',N'bigint') [Physical_reads]
			,event_data.value(N'(event/data[@name="writes"]/value)[1]',N'bigint') [Writes]
			,event_data.value(N'(event/data[@name="cpu_time"]/value)[1]',N'bigint') [Cpu_time]
			,event_data.value(N'(event/data[@name="duration"]/value)[1]',N'bigint') [Duration]
			,event_data.value(N'(event/action[@name="object_name"]/value)[1]',N'varchar(100)') [object_name]
			,event_data.value(N'(event/action[@name="sql_text"]/value)[1]',N'varchar(max)') [Query]
			,event_data.value(N'(event/data[@name="statement"]/value)[1]',N'varchar(max)') [Statement]
			,event_data.value(N'(event/data[@name="error_number"]/value)[1]',N'int') [Error_number]
			,event_data.value(N'(event/data[@name="category"]/text)[1]',N'varchar(100)') [Error_category]
			,event_data.value(N'(event/data[@name="message"]/value)[1]',N'Varchar(2000)') [Error_Message]
			,[file_name]
			,file_offset
	from #extendedevents
end

go

USE [msdb]
GO

/****** Object:  Job [DBA - XE_TSQL_COLLECT]    Script Date: 23/06/2021 11:57:45 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]    Script Date: 23/06/2021 11:57:45 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DBA - XE_TSQL_COLLECT', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [sp_xe_tsqlcollect]    Script Date: 23/06/2021 11:57:45 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'sp_xe_tsqlcollect', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'exec dbo.sp_xe_tsqlcollect', 
		@database_name=N'DBA_HIST', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Diario a cada 2h', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=8, 
		@freq_subday_interval=2, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20210623, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'7605dbc7-065d-4b60-b88b-2a4f18b4f5dc'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO


