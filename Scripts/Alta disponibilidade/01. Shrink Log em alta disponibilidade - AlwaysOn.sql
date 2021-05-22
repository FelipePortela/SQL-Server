-- DBA: Felipe Portela
-- E-mail: felipelimaportela@gmail.com
-- Fun��o: Shrink de arquivos do Log de ambientes de alta disponibilidade sem perder a sincroniza��o do ambiente.
-- Obs.: Use com cuidado, n�o me responsabilizo por corrup��es causadas pelo uso desse script.
-- Tel: (61)99407-6591


use [BD_SIR] -- select database
BACKUP LOG [BD_SIR] to disk = 'NUL:' with NO_CHECKSUM, CONTINUE_AFTER_ERROR -- backup of log for clean archive log to database.
declare @fileId as int = (select file_id from sys.database_files where type_desc = 'LOG') -- select fileid of directory to archive of log.
DBCC SHRINKFILE (@fileId, EMPTYFILE) -- action of shrink.. 
