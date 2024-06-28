Import-Module SQLPS -DisableNameChecking

# Group
Get-ChildItem SQLSERVER:\Sql\SQLCLUSTER01\SQL2017\AvailabilityGroups | `
Test-SqlAvailabilityGroup # -ShowPolicyDetails | ft * -AutoSize


# Replica
Get-ChildItem SQLSERVER:\SqlSQLCLUSTER02\SQL2017\AvailabilityGroups\Test-Grp\AvailabilityReplicas | `
Test-SqlAvailabilityReplica #-ShowPolicyDetails | ft * -AutoSize

# Replicate State
Get-ChildItem SQLSERVER:\Sql\SqlSQLCLUSTER02\SQL2017\AvailabilityGroups\Test-Grp\DatabaseReplicaStates | `
Test-SqlDatabaseReplicaState #-ShowPolicyDetails | ft * -AutoSize
