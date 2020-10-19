-- Mata todas as conexões ativas e coloca o banco online, caso alguma conexão tome o lugar no single user
-- Retorna o banco para MULTI USER novamente..

USE master; 
GO
DECLARE @sql nvarchar(MAX);
SELECT @sql = ' KILL ' + CAST(session_id as varchar(5))
    FROM sys.dm_exec_sessions
    WHERE database_id = DB_ID(N'NomeDoBanco');
	SET @sql = @sql + N' ALTER DATABASE nomeDobanco SET MULTI_USER;';
EXEC sp_executesql @sql;
GO;


-- Execute primeiro esse..
ALTER DATABASE nomeDoBanco
SET SINGLE_USER WITH ROLLBACK IMMEDIATE

-- Execute esse aqui...
ALTER DATABASE nomeDoBanco MODIFY NAME = nomeDobanco

-- depois por último, esse..
ALTER DATABASE nomeDoBanco
SET MULTI_USER WITH ROLLBACK IMMEDIATE
