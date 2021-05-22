    /*
SELECT '

USE ['+name+']
GO
CREATE LOGIN [dominio\usuario] FROM WINDOWS WITH DEFAULT_DATABASE=[master]
GO
CREATE USER [ANTT\claudio.ramos] FOR LOGIN [ANTT\claudio.ramos]
GO
ALTER ROLE [db_datareader] ADD MEMBER [ANTT\claudio.ramos]
GO
ALTER ROLE [db_datawriter] ADD MEMBER [ANTT\claudio.ramos]
GO
'
from sys.databases    */
	
	/*
		Dá permissão para todos os bancos para um usuário de desenvolvimento.
	
	*/
	