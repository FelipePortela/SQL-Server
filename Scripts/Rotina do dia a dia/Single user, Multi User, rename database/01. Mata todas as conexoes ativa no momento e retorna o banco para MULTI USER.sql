-- Mata todas as conex�es ativas e coloca o banco online, caso alguma conex�o tome o lugar no single user
-- Retorna o banco para MULTI USER novamente..

USE master; 
GO
DECLARE @sql nvarchar(MAX);
SELECT @sql = ' KILL ' + CAST(session_id as varchar(5))
    FROM sys.dm_exec_sessions
    WHERE database_id = DB_ID(N'BD_SIFAMA');
	SET @sql = @sql + N' ALTER DATABASE BD_SIFAMA SET MULTI_USER;';
EXEC sp_executesql @sql;
GO;


-- Execute primeiro esse..
ALTER DATABASE [BD_SIFAMA_19062020]
SET SINGLE_USER WITH ROLLBACK IMMEDIATE

-- Execute esse aqui...
ALTER DATABASE [BD_SIFAMA_19062020] MODIFY NAME = BD_SIFAMA

-- depois por �ltimo, esse..
ALTER DATABASE BD_SIFAMA
SET MULTI_USER WITH ROLLBACK IMMEDIATE
