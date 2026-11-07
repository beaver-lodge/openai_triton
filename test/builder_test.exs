defmodule OpenAITriton.BuilderTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  @tag :tmp_dir
  test "builds object libraries, bundles a linkable archive, and copies generated headers", %{
    tmp_dir: tmp
  } do
    source = Path.join(tmp, "source with spaces")
    llvm = Path.join(tmp, "llvm")
    out = Path.join(tmp, "output")
    for path <- ["lib", "include", "third_party"], do: File.mkdir_p!(Path.join(source, path))
    File.mkdir_p!(Path.join(llvm, "bin"))
    config = Path.join(llvm, "bin/llvm-config")

    File.write!(
      config,
      "#!/bin/sh\ncase \"$1\" in\n--libdir) printf '%s\\n' '#{llvm}/lib';;\n--version) printf 'test-llvm\\n';;\nesac\n"
    )

    File.chmod!(config, 0o755)

    File.write!(Path.join(source, "CMakeLists.txt"), """
    cmake_minimum_required(VERSION 3.20)
    project(CompilerFixture C)
    file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/include" "${CMAKE_BINARY_DIR}/third_party")
    file(WRITE "${CMAKE_BINARY_DIR}/include/generated.h" "generated")
    file(WRITE "${CMAKE_BINARY_DIR}/third_party/generated.h" "third-party generated")
    add_subdirectory(lib)
    """)

    targets = ~w(TritonIR TritonGPUIR TritonNvidiaGPUIR TritonInstrumentIR GluonIR
      TritonTransforms TritonGPUTransforms TritonNvidiaGPUTransforms TritonInstrumentTransforms
      GluonTransforms TritonToTritonGPU TritonGPUToLLVM TritonLLVMIR TritonAnalysis TritonTools
      NVGPUIR NVWSIR NVWSTransforms NVGPUToLLVM TritonNVIDIAGPUToLLVM NVHopperTransforms)

    File.write!(
      Path.join(source, "lib/CMakeLists.txt"),
      Enum.map_join(targets, "\n", fn target ->
        File.write!(
          Path.join(source, "lib/#{target}.c"),
          "int fixture_#{target}(void) { return 1; }\n"
        )

        "add_library(#{target} OBJECT #{target}.c)"
      end)
    )

    File.write!(Path.join(source, "include/source.h"), "source")

    capture_io(fn ->
      assert OpenAITriton.Builder.build!(
               source: source,
               llvm: llvm,
               output: out,
               ccache: "OFF",
               tmp_dir: tmp
             ) == out
    end)

    assert File.read!(Path.join(out, "include/source.h")) == "source"
    assert File.read!(Path.join(out, "include/generated.h")) == "generated"

    assert File.read!(Path.join(out, "include/third_party/generated.h")) ==
             "third-party generated"

    client = Path.join(tmp, "client.c")
    exe = Path.join(tmp, "client")

    File.write!(
      client,
      "int fixture_TritonIR(void); int main(void) { return fixture_TritonIR() != 1; }\n"
    )

    assert {_, 0} =
             System.cmd("cc", [client, Path.join(out, "lib/libtriton_core.a"), "-o", exe],
               stderr_to_stdout: true
             )

    assert {"", 0} = System.cmd(exe, [])
    assert Path.wildcard(Path.join(tmp, "triton-build-*")) == []
  end
end
