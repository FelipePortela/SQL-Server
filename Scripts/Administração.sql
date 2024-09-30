--Modificar tamanho arquivo dos arquivos
--Aumentar
ALTER DATABASE [Database] MODIFY FILE ( NAME = N'file_name', SIZE = 100MB )

--Reduzir passar tamanho MB
dbcc shrinkfile ('file_name',500) 
--Pode ser colocado em um loop para liberar de pouco a pouco sem travar o arquivo
declare @size int
set @size = 16750 --Tamanho Inicial
while (@size >= 14750) --Tamanho alvo
begin
	dbcc shrinkfile ('file_name',@size)
	set @size = @size - 250 --Redução por loop em MB
end

--Trocar tabela de Schema
alter schema [schemanovo] transfer [schema].[tabela]

--Alter database recovery model
alter database [database] set recovery simple --full --simple -bulk_logged

--Ler errorlog
exec sp_readerrorlog 0,1 --Log atual 
EXEC xp_readerrorlog 
	0, --0 log corrente, 1 log anterior, 2 3 4....
	1, --1 Error log SQL Server, 2 Error log agent
	null, --Busca de texto 1 ex: backup, login...
	null, --Busca de texto 2 ex: failed, error...
	'20190101', --Data inicial
	'20190102', --Data final
	'asc' --Ordenação ex: asc desc

--AlterCriação e modificações de login
create login [dominio\login] from windows with default_database=[master] --Windows
create login [Login] with password=N'Senha' must_change, default_database=[master], check_expiration=on, check_policy=on --SQL
alter login zabbix disable --ou enable para habilitar usuário

--Inclusão do login em server role
exec sys.sp_addsrvrolemember @loginame = N'login', @rolename = N'sysadmin'

--Criação do usuário em database
create user [usuario] for login [login]

--Inclusão e exclusão do login em database role
exec sys.sp_addrolemember @rolename = N'db_owner', @loginame = 'usuario'
alter role [role] add member [usuario]
alter role [role] drop member [usuario]

--Iniciar Job
exec msdb.dbo.sp_start_job @job_name = 'Nome do job', @server_name = @@SERVERNAME

--Verifica status databae mail
exec sysmail_help_status_sp
--Inicia database mail
exec sysmail_start_sp  

--Informações database
DBCC DBInfo() With TableResults, NO_INFOMSGS

--Configurações do banco de dados
select * from sys.database_scoped_configurations