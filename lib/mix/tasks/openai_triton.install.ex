defmodule Mix.Tasks.OpenaiTriton.Install do
  use Mix.Task
  @shortdoc "Install Triton core, or its paired LLVM with --llvm-only"
  def run(args), do: OpenAITriton.run(args)
end
