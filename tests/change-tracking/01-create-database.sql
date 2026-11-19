/*
    Change Tracking test, step 1 of 3.
    Run on a master connection.  Creates the scratch database.

    The guard reads sys.databases: on a master connection DB_ID() returns NULL
    for an existing user database.
*/
IF NOT EXISTS (SELECT 1 FROM [sys].[databases] AS [d] WHERE [d].[name] = N'ct_test_scratch')
BEGIN
    CREATE DATABASE [ct_test_scratch];
END;
