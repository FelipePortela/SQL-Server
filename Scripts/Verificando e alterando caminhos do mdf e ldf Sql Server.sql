-- Conferindo o resultado após a alteração

-- Local dos arquivos
SELECT name, physical_name 
FROM sys.master_files 
WHERE database_id = DB_ID('TreinamentoDBA');

-- 3. Altera o status da database para OFFLINE:
ALTER DATABASE TreinamentoDBA SET OFFLINE

-- *.mdf
ALTER DATABASE TreinamentoDBA MODIFY FILE ( NAME = TreinamentoDBA, FILENAME = 'C:\TEMP\TreinamentoDBA.mdf')

-- *.ldf
ALTER DATABASE TreinamentoDBA MODIFY FILE ( NAME = TreinamentoDBA_log, FILENAME = 'C:\TEMP\TreinamentoDBA_log.ldf')

-- 5. Altera o status da database para ONLINE:
ALTER DATABASE TreinamentoDBA SET ONLINE

