-- cluster info
SELECT *
FROM sys.dm_hadr_cluster_members


-- groups info
-- recovery + synchronization state
SELECT 
	g.name as ag_name,
	rgs.*
FROM sys.dm_hadr_availability_group_states as rgs
JOIN sys.availability_groups AS g
				 ON rgs.group_id = g.group_id


-- replicas info
-- Operational health : Pending failover,  Pending,  Online, Offline, Failed, Failed, no quorum
-- Recovery health    : ONLINE_IN_PROGRESS (at least one database not joined yet), 
--                      ONLINE (all databases joined) 
-- Synchro health     : NOT_HEALTHY (At least one joined database is in the NOT SYNCHRONIZING state) 
--                      PARTIALLY_HEALTHY (Some replicas are not in the target synchronization state SYNCHRONIZED or SYNCHRONIZING)
--                      HEALTHY
SELECT 
	g.name as ag_name,
	r.replica_server_name,
	rs.*
FROM sys.dm_hadr_availability_replica_states AS rs
JOIN sys.availability_replicas AS r
	ON rs.replica_id = r.replica_id
JOIN sys.availability_groups AS g
	ON g.group_id = r.group_id



-- databases info
-- synchro health : NOT SYNCHRONIZING (primary db --> is not ready to synchronize its transaction log with the corresponding secondary databases)
--                                    (secondary db --> has not started log synchronization because of a connection issue, is being suspended, or is going through transition states during startup or a role switch)
--                  SYNCHRONIZING     (primary db --> is ready to accept a scan request from a secondary database)
--                                    (secondary db --> active data movement is occurring for the database)
--                  SYNCHRONIZED      (A primary db shows SYNCHRONIZED in place of SYNCHRONIZING)
--                                    (secondary db --> synchronized when the local cache says the database is failover ready and is synchronizing)
--                  REVERTING         (Indicates the phase in the undo process when a secondary database is actively getting pages from the primary database
--                                     If force failover cannot be a primary (unstable situation))
--                  INITIALIZING      (Indicates the phase of undo when the transaction log required for a secondary database to catch up to the 
--                                     undo LSN is being shipped and hardened on a secondary replica)
-- Synchro health     : NOT_HEALTHY (At least one joined database is in the NOT SYNCHRONIZING state) 
--                      PARTIALLY_HEALTHY (A database on a synchronous-commit availability replica is considered partially healthy if synchronization_state is 1 (SYNCHRONIZING).)
--                      HEALTHY (synchronous db --> SYNCHRONIZED, asynchronous db --> SYNCHRONIZING)
SELECT 
	g.name as ag_name,
	r.replica_server_name,
	drs.*
FROM sys.dm_hadr_database_replica_states AS drs
		 JOIN sys.availability_replicas AS r
		  ON r.replica_id = drs.replica_id
		 JOIN sys.availability_groups AS g
		  ON g.group_id = drs.group_id
ORDER BY g.name, drs.is_primary_replica DESC