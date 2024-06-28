USE [master];
GO

IF DB_ID('dbi_tools') IS NOT NULL
BEGIN
	ALTER DATABASE [dbi_tools] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
	DROP DATABASE [dbi_tools];
END

CREATE DATABASE [dbi_tools];
GO

USE [dbi_tools]
GO


/****** Object:  Table [dbo].[dbi_alwayson_failover_logs]    Script Date: 05.02.2015 15:28:28 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO

CREATE TABLE [dbo].[dbi_alwayson_failover_logs](
	[event_time] [datetime] NOT NULL DEFAULT (getdate()),
	[group_name] [sysname] NOT NULL,
	[primary_replica_old] [varchar](128) NULL,
	[primary_replica_new] [varchar](128) NOT NULL,
	[primary_recovery_health] [nvarchar](80) NULL,
	[sent_by_email] [bit] NULL
) ON [PRIMARY]

GO

SET ANSI_PADDING ON
GO


/****** Object:  StoredProcedure [dbo].[dbi_alwayson_detect_failover]    Script Date: 05.02.2015 15:17:01 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [dbo].[dbi_alwayson_detect_failover]
(
	@debug BIT = 0
)
AS
/************************************
*   dbi-services SA, Switzerland    *
*   http://www.dbi-services.com        *
*************************************
    Group/Privileges..: DBA
    Script Name......: dbi_alwayson_detect_failover.sql
    Author...........: David Barbarin
    Date.............: 14.10.2014
    Version..........: SQL Server 2012
    Description......: Stored procedure to detect availability groups failover 
    Input parameters.: 
    Output parameters:
    Called by........: 
************************************
    Historical
    Date        Version    Who    Whats
    ----------  -------    ---    --------
    2014.10.14  1.0        DAB    Creation
*************************************/

SET NOCOUNT ON;

DECLARE @t_aag TABLE
(
   group_name SYSNAME NULL,
   primary_replica VARCHAR(128) NOT NULL,
   primary_recovery_health NVARCHAR(80) NULL
);

DECLARE @sql NVARCHAR(MAX) = N'';

DECLARE @t_aag_result TABLE
(
   [action] VARCHAR(50) NOT NULL, 
   group_name SYSNAME NOT NULL,
   primary_replica_old VARCHAR(128) NULL,
   primary_replica_new VARCHAR(128) NULL,
   primary_recovery_health NVARCHAR(80) NULL
);

--WHILE 1 = 1
--BEGIN

	-- insert last configuration from dbi_alwayson_failover_logs
	INSERT @t_aag 
	SELECT 
		group_name, 
		primary_replica_new,
		primary_recovery_health
	FROM [dbo].[dbi_alwayson_failover_logs];

   -- get current configuration and compare 
   WITH aag
   AS
   (
      SELECT 
       g.name AS group_name,
       primary_replica,
       primary_recovery_health_desc
      FROM sys.dm_hadr_availability_group_states AS ags
       JOIN sys.availability_groups AS g
        ON ags.group_id = g.group_id
   )
   MERGE @t_aag AS t_aag
   USING aag
    ON aag.group_name = t_aag.group_name 
   WHEN matched AND aag.primary_replica != t_aag.primary_replica 
    THEN UPDATE SET primary_replica = aag.primary_replica,
                    primary_recovery_health = aag.primary_recovery_health_desc
   WHEN NOT MATCHED BY TARGET 
    THEN INSERT VALUES (aag.group_name, aag.primary_replica, aag.primary_recovery_health_desc)
   WHEN NOT MATCHED BY SOURCE 
    THEN DELETE
   OUTPUT $action, COALESCE(inserted.group_name, deleted.group_name), deleted.primary_replica, inserted.primary_replica, inserted.primary_recovery_health
   INTO @t_aag_result;

   -- DEBUG
   IF @debug = 1
   BEGIN
	SELECT * FROM @t_aag;
	SELECT * FROM @t_aag_result;
   END

   -- insert new group
   INSERT [dbo].[dbi_alwayson_failover_logs] (group_name, primary_replica_old, primary_replica_new, primary_recovery_health)
   SELECT 
	group_name, 
    primary_replica_old, 
    primary_replica_new, 
    primary_recovery_health 
   FROM @t_aag_result
   WHERE [action] = 'insert';

   -- delete old group
   DELETE FROM [dbo].[dbi_alwayson_failover_logs]
   WHERE group_name IN (SELECT group_name  
                        FROM @t_aag_result
						WHERE [action] = 'delete');

   -- update groups only when changes are detected
   UPDATE al
	SET al.primary_replica_old = r.primary_replica_old,
	    al.primary_replica_new = r.primary_replica_new,
		al.primary_recovery_health = r.primary_recovery_health
   FROM [dbo].[dbi_alwayson_failover_logs] AS al
	JOIN @t_aag_result AS r
		ON r.group_name = al.group_name
   WHERE [action] = 'update';

   SELECT @sql = @sql + 'Group : ' + group_name + ' - old primary : ' + primary_replica_old + ' - new primary : ' + primary_replica_new + CHAR(13)
   FROM @t_aag_result
   WHERE [action] = 'update'
	AND primary_replica_new = @@SERVERNAME -- we send email only on the new primary replica to avoid duplicate emails

   IF LEN(@sql) > 0
   BEGIN
	-- DEBUG
	IF @debug = 1 PRINT @sql;

	-- Send email if failover is detected
	SELECT 'Failover detected'
	SELECT @sql
   END

  

   -- Reset work table
   DELETE FROM @t_aag_result;
   DELETE FROM @t_aag;
   SET @sql= N'';

--   WAITFOR DELAY '00:00:10';
--END
GO

/****** Object:  StoredProcedure [dbo].[dbi_alwayson_monitoring_availability_group_health]    Script Date: 05.02.2015 15:17:01 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[dbi_alwayson_monitoring_availability_group_health]
(
	@debug BIT = 0
)
AS

DECLARE @failure_detect_quorum BIT = 0;
DECLARE @failure_detect_cluster_nodes BIT = 0;
DECLARE @failure_detect_aag BIT = 0;
DECLARE @failure_detect_replica BIT = 0;
DECLARE @failure_detect_db BIT = 0;
DECLARE @sql VARCHAR(MAX);

--WHILE 1 = 1 
--BEGIN
	-- Format htlm document
	SET @sql = '
	<html>
	<body>
	 <head>
		<style type=''''text/css''''>
			table {
			font-size : 9pt;
			font-family : Arial;
			}

			td {
			border: thin solid #6495ed;
			}

			th {
			text-align : left;
			font-family: monospace;
			font-weight: bolder;
			border: thin solid #6495ed;
			}
	
		 </style>
	 </head>';

	-- cluster level
	IF EXISTS (SELECT 1
			   FROM sys.dm_hadr_cluster
			   WHERE quorum_state_desc <> 'NORMAL_QUORUM')
	BEGIN
		SET @failure_detect_quorum = 1;

		SET @sql = @sql + '
			<table>
			 <tr>
			  <th>Cluster Name</th>
			  <th>Quorum Type</th>
			  <th>Quorum State</th>
			 </tr>
		' + CHAR(13);

		SELECT 
		 @sql = @sql +
			'<tr>
			  <td>' + cluster_name + '</td>
			  <td>' + quorum_type_desc + '</td>
			  <td>' + quorum_state_desc + '</td>
			</tr>' + CHAR(13)
		FROM sys.dm_hadr_cluster;

		SET @sql = @sql + '</table><br /><br />' + CHAR(13) + CHAR(13);
	END

	-- DEBUG
	IF @debug = 1 PRINT @sql;

	IF (@sql IS NULL)
	 SET @sql = '';

	IF EXISTS (SELECT 1
			   FROM sys.dm_hadr_cluster_members
			   WHERE member_state_desc <> 'UP')
	BEGIN
		SET @failure_detect_cluster_nodes = 1;

		SET @sql = @sql + 
			'<table>
			  <tr>
			   <th>Cluster Node Member</th>
			   <th>Cluster Node Type</th>
			   <th>Cluster Node Stater</th>
			  </tr>
			' + CHAR(13);

		 SELECT @sql = @sql +
			'<tr>
			 <td>' + member_name + '</td>
			 <td>' + member_type_desc + '</td>
			 <td>' + member_state_desc + '</td>
			</tr>' + CHAR(13)
		FROM sys.dm_hadr_cluster_members;

		SET @sql = @sql + '</table><br /><br />' + CHAR(13) + CHAR(13);
	END

	-- DEBUG
	IF @debug = 1 PRINT @sql;

	IF (@sql IS NULL)
	 SET @sql = '';


	-- Group level
	IF EXISTS (SELECT 1
			   FROM sys.dm_hadr_availability_group_states AS rgs
				JOIN sys.availability_groups AS g
				 ON rgs.group_id = g.group_id
			   WHERE (CASE 
					  WHEN rgs.primary_recovery_health IS NULL THEN rgs.secondary_recovery_health_desc
					  ELSE  rgs.primary_recovery_health_desc
					 END <> 'ONLINE')
					  -- Verification of synchronization health only on the primary replica
					  -- We don't have any information about synchronization state on the secondaries
					  OR (CASE 
						   WHEN rgs.primary_recovery_health IS NOT NULL THEN synchronization_health_desc
						   ELSE 'HEALTHY'
						  END <> 'HEALTHY')
			  )
	BEGIN
		SET @failure_detect_aag = 1;

		SET @sql = @sql + 
			'<table>
			  <tr>
			   <th>Group Name</th>
			   <th>Replica</th>
			   <th>Replica recovery health</th>
			   <th>Synchronization health</th>
			  </tr>
			' + CHAR(13);

		SELECT @sql = @sql +
		 '<tr>
		   <td>' + g.name + '</td>
		   <td>' + CASE 
					WHEN rgs.primary_recovery_health IS NULL THEN 'secondary replica : ' + @@SERVERNAME
					ELSE 'Primary replica : ' + @@SERVERNAME
				   END + '</td>
		   <td>' + CASE 
					WHEN rgs.primary_recovery_health IS NULL THEN COALESCE(rgs.secondary_recovery_health_desc, 'N/A')
					ELSE COALESCE(rgs.primary_recovery_health_desc, 'N/A')
				   END + '</td>
		   <td>' + CASE
					WHEN rgs.primary_recovery_health IS NOT NULL THEN rgs.synchronization_health_desc
					ELSE 'N/A'
				   END+ '</td>
		  </tr>' + CHAR(13)
		FROM sys.dm_hadr_availability_group_states AS rgs
		 JOIN sys.availability_groups AS g
		  ON rgs.group_id = g.group_id
		 WHERE (CASE 
				 WHEN rgs.primary_recovery_health IS NULL THEN rgs.secondary_recovery_health_desc
				 ELSE  rgs.primary_recovery_health_desc
				END <> 'ONLINE')
				-- Verification of synchronization health only on the primary replica
				-- We don't have any information about synchronization state on the secondaries
				 OR (CASE 
					  WHEN rgs.primary_recovery_health IS NOT NULL THEN synchronization_health_desc
					  ELSE 'HEALTHY'
					 END <> 'HEALTHY')

		SET @sql = @sql + '</table><br /><br />' + CHAR(13) + CHAR(13);
	END

	-- DEBUG
	IF @debug = 1 PRINT @sql;

	IF (@sql IS NULL)
	 SET @sql = '';


	-- Replica level
	IF EXISTS (SELECT 1
			   FROM sys.dm_hadr_availability_replica_states AS rs
				JOIN sys.availability_replicas AS r
				 ON rs.replica_id = r.replica_id
				JOIN sys.availability_groups AS g
				 ON g.group_id = r.group_id
			   WHERE rs.synchronization_health_desc <> 'HEALTHY'
				OR rs.connected_state_desc <> 'CONNECTED'
			  )
	BEGIN
		SET @failure_detect_replica = 1;

		SET @sql = @sql + 
			'<table>
			  <tr>
			   <th>Group Name</th>
			   <th>Replica</th>
			   <th>Replica Role</th>
			   <th>Recovery Health</th>
			   <th>Synchronization Health</th>
			   <th>Connection State</th>
			   <th>Operational State</th>
			  </tr>
			' + CHAR(13);


		SELECT @sql = @sql +
		 '<tr>
		   <td>' + g.name + '</td>
		   <td>' + r.replica_server_name + '</td>
		   <td>' + rs.role_desc + '</td>
		   <td>' + COALESCE(rs.recovery_health_desc, 'N/A') + '</td>
		   <td>' + rs.synchronization_health_desc + '</td>
		   <td>' + rs.connected_state_desc + '</td>' + CHAR(13) +
		   -- describes whether the replica is ready to process client request for all databases of availability replica
		   '<td>' + COALESCE(rs.operational_state_desc, 'N/A') + '</td>
		 </tr>' + CHAR(13)
		FROM sys.dm_hadr_availability_replica_states AS rs
		 JOIN sys.availability_replicas AS r
		  ON rs.replica_id = r.replica_id
		 JOIN sys.availability_groups AS g
		  ON g.group_id = r.group_id
		WHERE rs.synchronization_health_desc <> 'HEALTHY'
				OR rs.connected_state_desc <> 'CONNECTED';

		SET @sql = @sql + '</table><br /><br />' + CHAR(13) + CHAR(13);
	END

	-- DEBUG
	IF @debug = 1 PRINT @sql;

	IF (@sql IS NULL)
	 SET @sql = '';

	-- Database level
	IF EXISTS (SELECT 1
			   FROM sys.dm_hadr_database_replica_states AS drs
				JOIN sys.availability_replicas AS r
				 ON r.replica_id = drs.replica_id
				JOIN sys.availability_groups AS g
				 ON g.group_id = drs.group_id
			   WHERE drs.synchronization_health_desc <> 'HEALTHY'
			  )
	BEGIN
		SET @failure_detect_db = 1;

		SET @sql = @sql + 
			'<table>
			  <tr>
			   <th>Group Name</th>
			   <th>Replica</th>
			   <th>Database</th>
			   <th>Synchronization Health</th>
			   <th>Synchronization State</th>
			   <th>Database State</th>
			   <th>Suspend Reason</th>
			  </tr>
			' + CHAR(13);

		SELECT @sql = @sql +
		 '<tr>
		   <td>' + g.name + '</td>
		   <td>' + CASE drs.is_local
					WHEN 1 THEN 'Local replica : ' +  r.replica_server_name
					ELSE 'Remote replica : ' +  r.replica_server_name
				   END + '</td>
		   <td>' + DB_NAME(drs.database_id) + '</td>
		   <td>' + drs.synchronization_health_desc + '</td>
		   <td>' + drs.synchronization_state_desc + '</td>
		   <td>' +  COALESCE(database_state_desc, '') + '</td>
		   <td>' + CASE drs.is_suspended 
					WHEN 1 THEN 'Suspended : ' + drs.suspend_reason_desc 
					ELSE ''
				   END + '</td>
		 </tr>' + CHAR(13)
		FROM sys.dm_hadr_database_replica_states AS drs
		 JOIN sys.availability_replicas AS r
		  ON r.replica_id = drs.replica_id
		 JOIN sys.availability_groups AS g
		  ON g.group_id = drs.group_id
		WHERE drs.synchronization_health_desc <> 'HEALTHY';

		SET @sql = @sql + '</table><br /><br />' + CHAR(13) + CHAR(13);
	END

	SET @sql = @sql + '</body></html>'

	IF @debug = 1
	BEGIN
		PRINT 'failure quorum          : ' + CAST(@failure_detect_quorum AS CHAR(1));
		PRINT 'failure cluster nodes   : ' + CAST(@failure_detect_cluster_nodes AS CHAR(1));
		PRINT 'failure aags            : ' + CAST(@failure_detect_aag AS CHAR(1));
		PRINT 'failure replicas        : ' + CAST(@failure_detect_replica AS CHAR(1));
		PRINT 'failure dbs             : ' + CAST(@failure_detect_replica AS CHAR(1));
	END

	IF @debug = 0
	BEGIN
		-- Send email if a problem is detected
		IF (@failure_detect_quorum = 1 OR @failure_detect_cluster_nodes = 1 OR @failure_detect_aag = 1
			OR @failure_detect_replica = 1 OR @failure_detect_db = 1)
		BEGIN
			PRINT 'Error detected ... sending email';
			
			SELECT 'Found AG not healthly'
			SELECT @sql
		END
	END
	ELSE
	BEGIN
		IF (@failure_detect_quorum = 1 OR @failure_detect_cluster_nodes = 1 OR @failure_detect_aag = 1
			OR @failure_detect_replica = 1 OR @failure_detect_db = 1)

			PRINT 'FAILURE DETECTED';
	END

	SET @failure_detect_quorum = 0;
	SET @failure_detect_cluster_nodes = 0;
	SET @failure_detect_aag = 0;
	SET @failure_detect_replica = 0;
	SET @failure_detect_db = 0;

--	WAITFOR DELAY '00:10:00';
--END

GO


