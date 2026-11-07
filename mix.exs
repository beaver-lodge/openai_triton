defmodule OpenAITriton.MixProject do
  use Mix.Project

  def project do
    [
      app: :openai_triton,
      version: "0.1.0",
      elixir: "~> 1.18",
      description: "Triton compiler toolchain installation and native core builds",
      package: [
        links: %{
          "Upstream" => "https://github.com/triton-lang/triton",
          "GitHub" => "https://github.com/beaver-lodge/openai_triton"
        },
        licenses: ["MIT"],
        files: ["lib", "priv", "mix.exs", ".formatter.exs", "README.md", "LICENSE"]
      ],
      deps: mlir_dep()
    ]
  end

  def application, do: [extra_applications: [:crypto, :inets, :ssl]]

  defp mlir_dep do
    case System.get_env("MLIR_TOOLCHAIN_PATH") do
      nil -> [{:mlir, "~> 0.1.0"}]
      path -> [{:mlir, path: Path.expand(path)}]
    end
  end
end
