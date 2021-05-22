select '

USE ['+name+']
GO
CREATE LOGIN [ANTT\claudio.ramos] FROM WINDOWS WITH DEFAULT_DATABASE=[master]
GO
CREATE USER [ANTT\claudio.ramos] FOR LOGIN [ANTT\claudio.ramos]
GO
ALTER ROLE [db_datareader] ADD MEMBER [ANTT\claudio.ramos]
GO
ALTER ROLE [db_datawriter] ADD MEMBER [ANTT\claudio.ramos]
GO
'
from sys.databases

-- Copiar resultado para word e executar o CTRL + U e substituir os seguintes parâmetros: 
								-- substituir espaço GO espaço: GO 
								-- para: ^pGO^p
