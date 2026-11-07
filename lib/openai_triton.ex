defmodule OpenAITriton do
  @moduledoc "Install Triton core libraries and the LLVM revision selected by Triton."
  @metadata_path Path.expand("../priv/toolchain.json", __DIR__)
  @external_resource @metadata_path
  def metadata,
    do:
      :openai_triton
      |> Application.app_dir("priv/toolchain.json")
      |> File.read!()
      |> JSON.decode!()

  def llvm_asset!(opts \\ []) do
    ref = opts[:triton_ref] || metadata()["triton_ref"]
    {os, arch} = MLIR.Toolchain.platform(opts)
    suffix = llvm_suffix(os, arch)
    fetch = opts[:fetch_json] || (&MLIR.Toolchain.github_get!/1)
    build = fetch.(metadata_url(ref, "cmake/llvm-build-info.json"))
    info = fetch.(metadata_url(ref, "cmake/llvm-info.json"))
    hash = info["llvm_hash"] || build["llvm_hash"]
    number = info["build_number"] || build["build_number"]

    unless is_binary(hash) and hash =~ ~r/^[0-9a-f]{40}$/ and is_integer(number) and number >= 0,
      do: Mix.raise("invalid Triton LLVM metadata")

    sha = get_in(info, ["sha256sum", suffix]) || opts[:sha256]
    if sha && not Regex.match?(~r/^[0-9a-fA-F]{64}$/, sha), do: Mix.raise("invalid LLVM checksum")
    name = "llvm-#{String.slice(hash, 0, 8)}-#{suffix}-#{number}.tar.gz"

    %{
      name: name,
      url: "https://oaitriton.blob.core.windows.net/public/llvm-builds/#{name}",
      sha256: sha,
      llvm_ref: hash,
      triton_ref: ref
    }
  end

  def core_asset!(opts \\ []) do
    ref = opts[:triton_ref] || metadata()["triton_ref"]
    platform = MLIR.Toolchain.platform(opts)

    suffix =
      case platform do
        {"manylinux", "x86_64"} ->
          "ubuntu-x86_64"

        {"macos", "arm64"} ->
          "macos-arm64"

        _ ->
          Mix.raise("no Triton core prebuilt for #{inspect(platform)}; use --llvm-only for LLVM")
      end

    name = opts[:asset_name] || "triton-#{ref}-#{suffix}.tar.gz"

    pinned? =
      ref == metadata()["triton_ref"] and is_nil(opts[:repo]) and
        is_nil(opts[:asset_url]) and is_nil(opts[:asset_name])

    checksum = opts[:sha256] || if(pinned?, do: metadata()["sha256"][suffix])

    %{
      name: name,
      url: core_url!(opts, ref, name),
      sha256: checksum,
      triton_ref: ref
    }
  end

  defp core_url!(opts, ref, name) do
    cond do
      opts[:asset_url] ->
        opts[:asset_url]

      opts[:repo] ->
        "https://github.com/#{opts[:repo]}/releases/download/triton-prebuilt-#{ref}/#{name}"

      true ->
        fetch = opts[:fetch_json] || (&MLIR.Toolchain.github_get!(&1, opts[:github_token]))
        id = metadata()["core_repository_id"]

        release =
          fetch.("https://api.github.com/repositories/#{id}/releases/tags/triton-prebuilt-#{ref}")

        case Enum.find(release["assets"] || [], &(&1["name"] == name)) do
          %{"browser_download_url" => url} when is_binary(url) -> url
          _ -> Mix.raise("core release #{ref} has no asset named #{name}")
        end
    end
  end

  def install_core!(asset, opts) do
    base = System.get_env("RUNNER_TEMP") || System.tmp_dir!()

    dir =
      MLIR.Toolchain.install_archive!(
        opts[:install_dir] || Path.join(base, "triton-prebuilt"),
        asset,
        "lib/libtriton_core.a"
      )

    output = "TRITON_PREBUILT_DIR=#{dir}\n"
    IO.write(output)
    if opts[:github_env], do: File.write!(opts[:github_env], output, [:append])
    dir
  end

  def run(args) do
    {opts, positional} =
      OptionParser.parse!(args,
        strict: MLIR.Toolchain.switches() ++ [llvm_only: :boolean, triton_ref: :string]
      )

    if length(positional) > 1, do: Mix.raise("expected at most one install directory")
    opts = Enum.reject(opts, fn {_key, value} -> value == "" end)

    opts =
      Enum.reduce(
        [
          triton_ref: "LLVM_TRITON_REF",
          asset_os: "LLVM_EUDSL_ASSET_OS",
          asset_arch: "LLVM_EUDSL_ASSET_ARCH",
          sha256: if(opts[:llvm_only], do: "LLVM_EUDSL_SHA256", else: "TRITON_CORE_SHA256"),
          github_env: "GITHUB_ENV",
          github_token: "GH_TOKEN",
          github_token: "GITHUB_TOKEN",
          install_dir: if(opts[:llvm_only], do: "LLVM_PREBUILT_DIR", else: "TRITON_PREBUILT_DIR")
        ],
        opts,
        fn {key, env}, acc ->
          case System.get_env(env) do
            value when value in [nil, ""] -> acc
            value -> Keyword.put_new(acc, key, value)
          end
        end
      )

    opts =
      if positional == [], do: opts, else: Keyword.put_new(opts, :install_dir, hd(positional))

    if opts[:print_metadata] do
      IO.puts(JSON.encode!(metadata()))
    else
      asset = if opts[:llvm_only], do: llvm_asset!(opts), else: core_asset!(opts)

      if opts[:resolve_only] || System.get_env("LLVM_EUDSL_RESOLVE_ONLY") == "1" do
        prefix = if opts[:llvm_only], do: "LLVM_PREBUILT", else: "TRITON_PREBUILT"
        IO.puts("#{prefix}_ASSET_NAME=#{asset.name}\n#{prefix}_URL=#{asset.url}")
        checksum_key = if opts[:llvm_only], do: "LLVM_EUDSL_SHA256", else: "TRITON_CORE_SHA256"
        if asset[:sha256], do: IO.puts("#{checksum_key}=#{asset.sha256}")
      else
        if opts[:llvm_only],
          do: MLIR.Toolchain.install_llvm!(asset, opts),
          else: install_core!(asset, opts)
      end
    end
  end

  def llvm_suffix(os, arch) do
    case {os, arch} do
      {"manylinux", "x86_64"} -> "ubuntu-x64"
      {"manylinux", "aarch64"} -> "ubuntu-arm64"
      {"macos", "arm64"} -> "macos-arm64"
      {"macos", "x86_64"} -> "macos-x64"
      {"windows", "amd64"} -> "windows-x64"
      other -> Mix.raise("no Triton LLVM archive for #{inspect(other)}")
    end
  end

  def metadata_url(ref, path),
    do: "https://raw.githubusercontent.com/triton-lang/triton/#{ref}/#{path}"
end
