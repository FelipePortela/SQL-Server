/*
	SELECT que verifica se existe replicação ativa para o banco de dados
*/

SELECT log_reuse_wait_desc
FROM sys.databases
WHERE name = 'DBName'