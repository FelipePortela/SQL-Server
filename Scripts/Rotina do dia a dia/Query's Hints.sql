-- QUERY's Hints..

-- Ao adicionar esse Hint no final, o SELECT passa a usar o plano de execução do SQL Server 2012, 
	--ou seja, após migração se um select estiver muito lento, teste.
	OPTION(QUERYTRACEON 9481) 

