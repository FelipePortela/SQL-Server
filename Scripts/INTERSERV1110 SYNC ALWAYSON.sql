declare @min int = 1, @max int, @cmd varchar(250)
declare @not_sync_db table (id int identity, [database] varchar(100))
insert into @not_sync_db
select 
    db_name(hdr.database_id)
from sys.availability_replicas ar
    join sys.dm_hadr_database_replica_states hdr
        on ar.replica_id = hdr.replica_id
where hdr.database_state > 0
set @max = @@rowcount

while @min <= @max
begin
	select 
		@cmd = 'ALTER DATABASE ['+[database]+'] SET HADR RESUME '
	from @not_sync_db 
	where id = @min

	exec(@cmd)
	
	set @min += 1

end
