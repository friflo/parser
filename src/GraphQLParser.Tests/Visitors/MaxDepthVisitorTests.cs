using GraphQLParser.Visitors;

namespace GraphQLParser.Tests.Visitors;

public class MaxDepthVisitorTests
{
    /// <summary>
    /// For structure examples see
    /// <see cref="StructurePrinterTests.StructurePrinter_Should_Print_Tree(string, string)"/>
    /// </summary>
    [Theory]
    [InlineData("query a { name age }", 5)]
    [InlineData("scalar Test", 3)]
    [InlineData("scalar JSON @exportable", 5)]
    [InlineData("{a}", 5)] // Document->OperationDefinition->SelectionSet->Field->Name
    [InlineData("{ a { b { c } d { e { f } } g { h { i { k } } } } }", 13)]
    public async Task MaxDepthVisitor_Should_Work(string text, int expectedMaxDepth)
    {
        var visitor = new MaxDepthVisitor<DefaultMaxDepthContext>();
        var context = new DefaultMaxDepthContext();
        context.CancellationToken.ShouldBe(CancellationToken.None);

        var document = text.Parse();

        await visitor.VisitAsync(document, context).ConfigureAwait(false);
        context.MaxDepth.ShouldBe(expectedMaxDepth);
        document.MaxNestedDepth().ShouldBe(expectedMaxDepth);
    }
}
