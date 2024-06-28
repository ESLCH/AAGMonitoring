USE master;

SELECT 
	g.name as ag_name,
	r.replica_server_name,
	rs.database_id,
	rs.is_local,
	rs.is_primary_replica,
	rs.log_send_queue_size as log_send_queue_KB,
	rs.log_send_rate as [log_sen_KB/s],
	rs.redo_queue_size as redo_queue_KB,
	rs.redo_rate as [redo_rate_KB/s],
        -- last blocks send
	rs.last_sent_lsn,
	rs.last_sent_time,
        -- last blocks received
	rs.last_received_lsn,
	rs.last_received_time,
	-- Tlog block hardened activity
	rs.last_hardened_lsn,
	rs.last_hardened_time,
	-- Redo 
	rs.last_redone_lsn,
	rs.last_redone_time,
	rs.last_commit_lsn,
	rs.last_commit_time
FROM sys.dm_hadr_database_replica_states AS rs
JOIN sys.availability_replicas AS r
	ON rs.replica_id = r.replica_id
JOIN sys.availability_groups AS g
	ON g.group_id = r.group_id
WHERE g.name = ' Killer-Grp'
GO


