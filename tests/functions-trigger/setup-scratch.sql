/*
    Functions SQL trigger test: objects in the scratch database.
    Run on a connection to [ct_func_scratch] after the login exists.
*/
CREATE USER [ct_func_test] FROM LOGIN [ct_func_test];

/* The trigger creates its own az_func schema and lease tables, so the test login owns this scratch database only. */
ALTER ROLE [db_owner] ADD MEMBER [ct_func_test];

ALTER DATABASE CURRENT SET CHANGE_TRACKING = ON (CHANGE_RETENTION = 2 DAYS, AUTO_CLEANUP = ON);

CREATE TABLE [dbo].[ToDo]
(
    [Id]     int           NOT NULL CONSTRAINT [pk_ToDo] PRIMARY KEY CLUSTERED
  , [Title]  nvarchar(200) NULL
);

ALTER TABLE [dbo].[ToDo] ENABLE CHANGE_TRACKING;
