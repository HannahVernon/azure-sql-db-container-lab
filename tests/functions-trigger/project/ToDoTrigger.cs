using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Extensions.Sql;
using Microsoft.Extensions.Logging;

namespace CtFuncTest;

public sealed class ToDoItem
{
    public int Id { get; set; }
    public string? Title { get; set; }
}

/// <summary>Writes one line per change that the Azure SQL trigger delivers.</summary>
public sealed class ToDoTrigger
{
    private readonly ILogger<ToDoTrigger> _logger;

    public ToDoTrigger(ILogger<ToDoTrigger> logger) => _logger = logger;

    [Function("ToDoTrigger")]
    public void Run([SqlTrigger("[dbo].[ToDo]", "SqlConnectionString")] IReadOnlyList<SqlChange<ToDoItem>> changes)
    {
        var path = Path.Combine(AppContext.BaseDirectory, "changes.log");
        foreach (var change in changes)
        {
            var line = $"{change.Operation} Id={change.Item.Id} Title={change.Item.Title}";
            _logger.LogInformation("SQL trigger fired: {Line}", line);
            File.AppendAllText(path, line + Environment.NewLine);
        }
    }
}
