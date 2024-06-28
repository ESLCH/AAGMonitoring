USE [master];
GO

CREATE DATABASE [killerdb]
 ON  PRIMARY 
( NAME = N'killerdb', FILENAME = N'C:\MountPoints\Data\SQL14\killerdb.mdf' , SIZE = 3145728KB , FILEGROWTH = 524288KB )
 LOG ON 
( NAME = N'killerdb_log', FILENAME = N'C:\MountPoints\LogSlow\SQL14\killerdb_log.ldf' , SIZE = 2097152KB , FILEGROWTH = 524288KB)
GO

BACKUP DATABASE [killerdb] TO DISK = 'C:\Program Files\Microsoft SQL Server\MSSQL12.SQL14\MSSQL\Backup\killerdb.bak'

--> Create availability group Killer-Grp

USE [killerdb];
GO

CREATE TABLE dbo.killer_t
(
	col1 CHAR(200) DEFAULT REPLICATE('T', 150)
)


INSERT  dbo.killer_t DEFAULT VALUES;


--TRUNCATE TABLE dbo.killer_t
--BACKUP LOG [killerdb] TO DISK = 'C:\Program Files\Microsoft SQL Server\MSSQL12.SQL14\MSSQL\Backup\killerdb.trn' WITH INIT, COMPRESSION