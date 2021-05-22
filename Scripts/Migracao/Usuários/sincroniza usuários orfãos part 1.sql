DECLARE @Collation varchar(100)
DECLARE @SQL VARCHAR(2000)
CREATE TABLE ##TempSync
(
DB_NME Varchar(50),
DBUserName varchar(50),
SysLoginName varchar(50)
)
SELECT @Collation = CONVERT(SYSNAME,DatabasePropertyEx('master','Collation'))
SET @SQL = 'USE [?]
SELECT ''?'' DB_NME,
       A.name DBUserName,
       B.loginname SysLoginName
 FROM sysusers A
      JOIN master.dbo.syslogins B
      ON A.name Collate ' + @Collation + ' = B.Name 
      JOIN master.dbo.sysdatabases C
      ON C.Name = ''?''
 WHERE issqluser = 1
       AND (A.sid IS NOT NULL
       AND A.sid <> 0x0)
       AND suser_sname(A.sid) IS NULL
       AND (C.status & 32) =0 --loading
       AND (C.status & 64) =0 --pre recovery
       AND (C.status & 128) =0 --recovering
       AND (C.status & 256) =0 --not recovered
       AND (C.status & 512) =0 --offline
       AND (C.status & 1024) =0 --read only
 ORDER BY A.name'
INSERT into ##TempSync
EXEC sp_msforeachdb @SQL
SELECT * FROM ##TempSync
DROP TABLE ##TempSync