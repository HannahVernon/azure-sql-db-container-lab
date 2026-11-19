/*
    Build check for the Azure SQL Database container.
    Run on a master connection.  Read-only.

    EngineEdition 5 is Azure SQL Database.  If it returns anything else, the
    container is running the SQL Server image instead.
*/
SET NOCOUNT ON;

SELECT
    [version]          = @@VERSION
  , [product_version]  = CONVERT(nvarchar(128), SERVERPROPERTY(N'ProductVersion'))
  , [product_level]    = CONVERT(nvarchar(128), SERVERPROPERTY(N'ProductLevel'))
  , [edition]          = CONVERT(nvarchar(128), SERVERPROPERTY(N'Edition'))
  , [engine_edition]   = CONVERT(int, SERVERPROPERTY(N'EngineEdition'))
  , [collation]        = CONVERT(nvarchar(128), SERVERPROPERTY(N'Collation'));
