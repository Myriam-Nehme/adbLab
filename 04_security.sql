USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'TicketHubApp')
    CREATE LOGIN TicketHubApp
        WITH PASSWORD        = N'<<CHANGE_ME_Strong_Password_1!>>',   -- placeholder, change it
             DEFAULT_DATABASE = TicketHub,
             CHECK_POLICY     = ON;                                   -- Windows password rules
GO

USE TicketHub;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'TicketHubApp')
    CREATE USER TicketHubApp FOR LOGIN TicketHubApp;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'TicketHubAppRole' AND type = 'R')
    CREATE ROLE TicketHubAppRole;
GO

ALTER ROLE TicketHubAppRole ADD MEMBER TicketHubApp;
GO

GRANT EXECUTE ON SCHEMA::app        TO TicketHubAppRole;
GRANT EXECUTE ON TYPE::app.SeatIdList TO TicketHubAppRole;
GO

DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO TicketHubAppRole;
GO

SELECT dp.name AS Principal, p.permission_name, p.state_desc, p.class_desc,
       CASE p.class_desc WHEN 'SCHEMA' THEN SCHEMA_NAME(p.major_id)
                         WHEN 'TYPE'   THEN TYPE_NAME(p.major_id) END AS OnObject
FROM sys.database_permissions p
JOIN sys.database_principals dp ON dp.principal_id = p.grantee_principal_id
WHERE dp.name = N'TicketHubAppRole';
GO
