--Servidor e versão 
SELECT 
    @@SERVERNAME AS [Server Name], 
    SERVERPROPERTY('IsClustered') AS [IsClustered], 
    serverproperty('computernamephysicalnetbios') [Computer Name],
    SERVERPROPERTY('ProductVersion') AS [ProductVersion],
    SERVERPROPERTY('Edition') AS [Edition], 
    SERVERPROPERTY('ProductLevel') AS [ProductLevel],
    SERVERPROPERTY('ProductUpdateLevel') AS [ProductUpdateLevel],
    SERVERPROPERTY('ProductUpdateReference') AS [ProductUpdateReference], 
    SERVERPROPERTY('Collation') AS [Collation], 
    SERVERPROPERTY('ProcessID') AS [ProcessID],
    SERVERPROPERTY('InstanceDefaultDataPath') AS [InstanceDefaultDataPath],
    SERVERPROPERTY('InstanceDefaultLogPath') AS [InstanceDefaultLogPath];

--Configurações da Instância
SELECT 
    name, value_in_use, [description]
FROM sys.configurations WITH (NOLOCK)
where name in (
                    'Ad Hoc Distributed Queries',
                    'Agent XPs',
                    'automatic soft-NUMA disabled',
                    'clr enabled',
                    'cost threshold for parallelism',
                    'Database Mail XPs',
                    'filestream access level',
                    'fill factor (%)',
                    'max degree of parallelism',
                    'max server memory (MB)',
                    'Ole Automation Procedures',
                    'optimize for ad hoc workloads',
                    'priority boost',
                    'Replication XPs',
                    'xp_cmdshell',
                    'remote admin connections',
                    'remote access'

            )
order by [name]

--drop table if exists #dbinfo;
create table #dbinfo(
    database_id int
    ,parentobject varchar(250)
    ,[object] varchar(250)
    ,[field] varchar(250)
    ,[value] varchar(250)
)
exec sp_MSforeachdb '
use [?];
insert into #dbinfo([parentobject],[object],[field],[value]) exec sp_executesql N''DBCC DBInfo() With TableResults, NO_INFOMSGS'';
update #dbinfo set database_id = db_id() where database_id is null;
'
select distinct db_name(database_id),database_id,field,value From #dbinfo
where field = 'dbi_dbccLastKnownGood'


select 
    db.[name],
    db.state_desc,
    db.recovery_model_desc,
    db.compatibility_level,
    db.collation_name,
    db.is_read_only,
    db.is_auto_close_on,
    db.is_auto_shrink_on,
    db.snapshot_isolation_state_desc,
    db.is_read_committed_snapshot_on,
    db.page_verify_option_desc,
    db.log_reuse_wait_desc
from sys.databases db
    left join ( select 
                    distinct database_id,
                    [value] 
                From #dbinfo
                where field = 'dbi_dbccLastKnownGood'
                ) checkdb
        on db.database_id = checkdb.database_id