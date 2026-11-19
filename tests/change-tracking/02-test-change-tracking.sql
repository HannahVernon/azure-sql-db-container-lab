/*
    Change Tracking test, step 2 of 3.
    Run on a connection to [ct_test_scratch].

    Each step reports success or the error it hit, rather than stopping, so a
    single run shows how far Change Tracking gets in this engine.
*/
SET NOCOUNT ON;

BEGIN TRY
    ALTER DATABASE CURRENT
        SET CHANGE_TRACKING = ON (CHANGE_RETENTION = 1 DAYS, AUTO_CLEANUP = ON);
    SELECT [step] = N'ALTER DATABASE ... SET CHANGE_TRACKING = ON', [result] = N'PASS';
END TRY
BEGIN CATCH
    SELECT [step] = N'ALTER DATABASE ... SET CHANGE_TRACKING = ON', [result] = CONCAT(N'FAIL: Msg ', ERROR_NUMBER(), N', ', ERROR_MESSAGE());
END CATCH;
GO

SELECT
    [database_name]       = DB_NAME([ctd].[database_id])
  , [is_auto_cleanup_on]  = [ctd].[is_auto_cleanup_on]
  , [retention_period]    = [ctd].[retention_period]
  , [retention_units]     = [ctd].[retention_period_units_desc]
FROM
    [sys].[change_tracking_databases] AS [ctd];
GO

IF OBJECT_ID(N'[dbo].[ct_probe]', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[ct_probe]
    (
        [id]    int          NOT NULL CONSTRAINT [pk_ct_probe] PRIMARY KEY CLUSTERED
      , [note]  nvarchar(50) NOT NULL
    );
END;
GO

BEGIN TRY
    ALTER TABLE [dbo].[ct_probe] ENABLE CHANGE_TRACKING;
    SELECT [step] = N'ALTER TABLE ... ENABLE CHANGE_TRACKING', [result] = N'PASS';
END TRY
BEGIN CATCH
    SELECT [step] = N'ALTER TABLE ... ENABLE CHANGE_TRACKING', [result] = CONCAT(N'FAIL: Msg ', ERROR_NUMBER(), N', ', ERROR_MESSAGE());
END CATCH;
GO

INSERT INTO [dbo].[ct_probe] ([id], [note])
VALUES (1, N'first change');
GO

BEGIN TRY
    DECLARE @changes bigint;

    SELECT
        @changes = COUNT_BIG(*)
    FROM
        CHANGETABLE(CHANGES [dbo].[ct_probe], 0) AS [ct];

    SELECT [step] = N'CHANGETABLE(CHANGES ...)', [result] = CONCAT(N'PASS: ', @changes, N' row(s); current version ', CHANGE_TRACKING_CURRENT_VERSION());
END TRY
BEGIN CATCH
    SELECT [step] = N'CHANGETABLE(CHANGES ...)', [result] = CONCAT(N'FAIL: Msg ', ERROR_NUMBER(), N', ', ERROR_MESSAGE());
END CATCH;
GO
