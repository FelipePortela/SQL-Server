insert into BDANTT23.BD_EMAIL.dbo.tblEmails
	SELECT 
	   13
      ,emailTemp.id
      ,emailTemp.email
      ,NULL
      ,NULL
  FROM ##emails as emailTemp


  -- duplicando os inserts da tabela tblotes

  insert into tblLotes ([IdLote]
      ,[Perfil]
      ,[De]
      ,[Retorno]
      ,[Assunto]
      ,[Corpo]
      ,[Formato]
      ,[DataRegistro]
      ,[QtdEmailsPorVez]
      ,[Restantes])
SELECT 101
      ,[Perfil]
      ,[De]
      ,[Retorno]
      ,[Assunto]
      ,[Corpo]
      ,[Formato]
      ,[DataRegistro]
      ,[QtdEmailsPorVez]
      ,[Restantes]
  FROM [BD_EMAIL].[dbo].[tblLotes] where IdLote = 16
