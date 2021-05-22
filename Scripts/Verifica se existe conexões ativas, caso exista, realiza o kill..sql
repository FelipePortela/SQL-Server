--	Segue query para encontrar as conex�es nessa database
select *
from sys.sysprocesses
where	Db_name(dbid) = 'TreinamentoDBA'
		and spid > 50	-- Apenas conexoes de usu�rios. spid < 50 � conex�o de sistema.

------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

-- 2. Verificar se existe alguma conex�o na database. Se existir, deve fazer matar com o KILL.
USE master 
Declare @SpId as varchar(5)

if(OBJECT_ID('tempdb..#Processos') is not null) drop table #Processos

select Cast(spid as varchar(5))SpId
into #Processos
from master.dbo.sysprocesses A
 join master.dbo.sysdatabases B on A.DbId = B.DbId
where B.Name ='TreinamentoDBA'

-- Mata as conex�es
while (select count(*) from #Processos) >0
begin
 set @SpId = (select top 1 SpID from #Processos)
   exec ('Kill ' +  @SpId)
 delete from #Processos where SpID = @SpId
end