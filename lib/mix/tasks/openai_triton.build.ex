defmodule Mix.Tasks.OpenaiTriton.Build do
  use Mix.Task
  @shortdoc "Build Triton core from a source checkout and paired LLVM"
  def run(args) do
    {opts, []} =
      OptionParser.parse!(args,
        strict: [source: :string, llvm: :string, output: :string, ccache: :string, cache: :string]
      )

    OpenAITriton.Builder.build!(opts)
  end
end
