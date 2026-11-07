defmodule OpenAITriton.Builder do
  @moduledoc "Build the native Triton core without its Python module."
  @targets ~w(TritonIR TritonGPUIR TritonNvidiaGPUIR TritonInstrumentIR GluonIR
    TritonTransforms TritonGPUTransforms TritonNvidiaGPUTransforms TritonInstrumentTransforms
    GluonTransforms TritonToTritonGPU TritonGPUToLLVM TritonLLVMIR TritonAnalysis TritonTools
    NVGPUIR NVWSIR NVWSTransforms NVGPUToLLVM TritonNVIDIAGPUToLLVM NVHopperTransforms)

  def build!(opts) do
    source = required!(opts, :source, "TRITON_SOURCE_DIR")
    llvm = required!(opts, :llvm, "LLVM_SYSPATH")
    out = required!(opts, :output, "TRITON_PREBUILT_OUTPUT_DIR")

    if out == source or out == llvm or out in [Path.expand("/"), System.user_home!()],
      do: Mix.raise("output must be a separate toolchain directory")

    config = Path.join(llvm, "bin/llvm-config")
    {libdir, 0} = System.cmd(config, ["--libdir"])
    {version, 0} = System.cmd(config, ["--version"])
    libdir = String.trim(libdir)

    build =
      Path.join(
        opts[:tmp_dir] || System.tmp_dir!(),
        "triton-build-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    try do
      run!("cmake", [
        "-S",
        source,
        "-B",
        build,
        "-G",
        "Ninja",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DTRITON_BUILD_PYTHON_MODULE=OFF",
        "-DTRITON_BUILD_UT=OFF",
        "-DTRITON_BUILD_PROTON=OFF",
        "-DTRITON_BUILD_WITH_CCACHE=#{opts[:ccache] || System.get_env("TRITON_BUILD_WITH_CCACHE") || "ON"}",
        "-DTRITON_CODEGEN_BACKENDS=nvidia",
        "-DTRITON_CACHE_PATH=#{opts[:cache] || System.get_env("TRITON_CACHE_PATH") || Path.join(System.user_home!(), ".triton")}",
        "-DLLVM_SYSPATH=#{llvm}",
        "-DMLIR_DIR=#{libdir}/cmake/mlir",
        "-DLLVM_DIR=#{libdir}/cmake/llvm"
      ])

      run!("ninja", ["-C", build | @targets])

      objects =
        for root <- ["lib", "third_party"],
            file <- Path.wildcard(Path.join([build, root, "**/*.o"])),
            String.contains?(file, "/CMakeFiles/"),
            do: file

      if objects == [], do: Mix.raise("no Triton object libraries built")
      File.mkdir_p!(Path.join(out, "lib"))
      archive = Path.join(out, "lib/libtriton_core.a")

      case :os.type() do
        {:unix, :darwin} ->
          run!("libtool", ["-static", "-o", archive | Enum.sort(objects)])

        {:unix, :linux} ->
          File.rm(archive)
          run!("ar", ["rcs", archive | Enum.sort(objects)])

        platform ->
          Mix.raise("unsupported Triton core build platform #{inspect(platform)}")
      end

      for {base, directory, target} <- [
            {source, "include", "include"},
            {build, "include", "include"},
            {source, "third_party", "include/third_party"},
            {build, "third_party", "include/third_party"}
          ] do
        File.cp_r!(Path.join(base, directory), Path.join(out, target))
      end

      File.write!(
        Path.join(out, "toolchain.json"),
        JSON.encode!(%{llvm_version: String.trim(version), targets: @targets})
      )

      out
    after
      File.rm_rf!(build)
    end
  end

  defp required!(opts, key, env) do
    value = opts[key] || System.get_env(env) || Mix.raise("#{env} or --#{key} required")
    Path.expand(value)
  end

  defp run!(command, args) do
    case System.cmd(command, args, stderr_to_stdout: true, into: IO.stream()) do
      {_, 0} -> :ok
      {_, status} -> Mix.raise("#{command} exited with #{status}")
    end
  end
end
