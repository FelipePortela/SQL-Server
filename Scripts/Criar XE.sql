declare @cmd varchar(2000), @path varchar(100) = (select top 1 left(log_file_path,2)+'\XE' from sys.server_file_audits)

exec master.dbo.xp_create_subdir @path

select @path+= '\TSQL - Monitor.xel'

select @cmd = '
CREATE EVENT SESSION [TSQL - Monitor] ON SERVER 
ADD EVENT sqlserver.error_reported(
    ACTION(sqlserver.client_hostname,sqlserver.database_name,sqlserver.sql_text,sqlserver.username)
    WHERE ([severity]>(17))),
ADD EVENT sqlserver.sp_statement_completed(SET collect_object_name=(1)
    ACTION(sqlserver.client_hostname,sqlserver.database_name,sqlserver.query_hash,sqlserver.sql_text,sqlserver.username)
    WHERE ([duration]>(5000000))),
ADD EVENT sqlserver.sql_statement_completed(
    ACTION(sqlserver.client_hostname,sqlserver.database_name,sqlserver.query_hash,sqlserver.sql_text,sqlserver.username)
    WHERE ([duration]>(5000000)))
ADD TARGET package0.event_file(SET filename='''+@path+''',max_file_size=(100),max_rollover_files=(10))
WITH (STARTUP_STATE=ON)
'
exec(@cmd)