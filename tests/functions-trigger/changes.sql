/*
    Functions SQL trigger test: the changes the function should report.
    Run on a connection to [ct_func_scratch] once the trigger listener has started.
*/
INSERT INTO [dbo].[ToDo] ([Id], [Title]) VALUES (1, N'first'), (2, N'second');
UPDATE [dbo].[ToDo] SET [Title] = N'second, updated' WHERE [Id] = 2;
DELETE FROM [dbo].[ToDo] WHERE [Id] = 1;
