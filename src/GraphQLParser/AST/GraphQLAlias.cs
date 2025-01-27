namespace GraphQLParser.AST;

/// <summary>
/// AST node for <see cref="ASTNodeKind.Alias"/>.
/// </summary>
public class GraphQLAlias : ASTNode, INamedNode
{
    /// <inheritdoc/>
    public override ASTNodeKind Kind => ASTNodeKind.Alias;

    /// <inheritdoc/>
    public GraphQLName Name { get; set; } = null!;
}

internal sealed class GraphQLAliasWithLocation : GraphQLAlias
{
    private GraphQLLocation _location;

    public override GraphQLLocation Location
    {
        get => _location;
        set => _location = value;
    }
}

internal sealed class GraphQLAliasWithComment : GraphQLAlias
{
    private List<GraphQLComment>? _comments;

    public override List<GraphQLComment>? Comments
    {
        get => _comments;
        set => _comments = value;
    }
}

internal sealed class GraphQLAliasFull : GraphQLAlias
{
    private GraphQLLocation _location;
    private List<GraphQLComment>? _comments;

    public override GraphQLLocation Location
    {
        get => _location;
        set => _location = value;
    }

    public override List<GraphQLComment>? Comments
    {
        get => _comments;
        set => _comments = value;
    }
}
