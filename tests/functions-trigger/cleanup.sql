/*
    Functions SQL trigger test: removes the scratch database and the test login.
    Run on a master connection.
*/
DROP DATABASE IF EXISTS [ct_func_scratch];

IF EXISTS (SELECT 1 FROM [sys].[sql_logins] AS [l] WHERE [l].[name] = N'ct_func_test')
BEGIN
    DROP LOGIN [ct_func_test];
END;
