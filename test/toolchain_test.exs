defmodule OpenAITritonTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  test "LLVM metadata binds a Triton ref, LLVM hash, build number and platform checksum" do
    ref = String.duplicate("a", 40)
    hash = String.duplicate("b", 40)
    checksum = String.duplicate("c", 64)

    fetch = fn url ->
      assert String.contains?(url, "/#{ref}/cmake/")

      if String.ends_with?(url, "llvm-info.json"),
        do: %{
          "llvm_hash" => hash,
          "build_number" => 7,
          "sha256sum" => %{"ubuntu-x64" => checksum}
        },
        else: %{}
    end

    asset =
      OpenAITriton.llvm_asset!(
        triton_ref: ref,
        asset_os: "manylinux",
        asset_arch: "x86_64",
        fetch_json: fetch
      )

    assert asset.name == "llvm-bbbbbbbb-ubuntu-x64-7.tar.gz"
    assert asset.sha256 == checksum
    assert asset.llvm_ref == hash
    assert asset.triton_ref == ref
  end

  test "rejects invalid LLVM identity and separates LLVM from core platform support" do
    assert_raise Mix.Error, ~r/invalid Triton LLVM metadata/, fn ->
      OpenAITriton.llvm_asset!(
        fetch_json: fn _ -> %{"llvm_hash" => "unknown", "build_number" => 1} end
      )
    end

    assert OpenAITriton.llvm_suffix("windows", "amd64") == "windows-x64"
    assert OpenAITriton.llvm_suffix("manylinux", "aarch64") == "ubuntu-arm64"

    assert_raise Mix.Error, ~r/no Triton core prebuilt/, fn ->
      OpenAITriton.core_asset!(asset_os: "windows", asset_arch: "amd64")
    end
  end

  test "core releases can move independently of Beaver" do
    asset =
      OpenAITriton.core_asset!(
        triton_ref: "commit",
        repo: "example/triton",
        asset_os: "macos",
        asset_arch: "arm64"
      )

    assert asset.url ==
             "https://github.com/example/triton/releases/download/triton-prebuilt-commit/triton-commit-macos-arm64.tar.gz"
  end

  test "pinned core assets carry their checksum without applying it to replacement archives" do
    asset = OpenAITriton.core_asset!(asset_os: "macos", asset_arch: "arm64")
    assert asset.sha256 == "e2ae3dfcf14e5a960c21c407d791aca84b88d0d90ad19a34b5174021221b3a6b"

    replacement =
      OpenAITriton.core_asset!(
        asset_os: "macos",
        asset_arch: "arm64",
        asset_url: "https://example.com/core.tar.gz"
      )

    assert is_nil(replacement.sha256)

    output =
      capture_io(fn ->
        OpenAITriton.run(["--resolve-only", "--asset-os", "macos", "--asset-arch", "arm64"])
      end)

    assert output =~ "TRITON_CORE_SHA256=#{asset.sha256}"
    refute output =~ "LLVM_EUDSL_SHA256="
  end

  @tag :tmp_dir
  test "installs a core-only artifact without invoking or overwriting LLVM", %{tmp_dir: tmp} do
    path = Path.join(tmp, "core.tar.gz")

    :ok =
      :erl_tar.create(
        String.to_charlist(path),
        [{~c"lib/libtriton_core.a", "archive"}, {~c"include/triton.h", "header"}],
        [:compressed]
      )

    asset = %{name: "core.tar.gz", url: "file://#{path}"}
    dest = Path.join(tmp, "core")

    output =
      capture_io(fn -> assert OpenAITriton.install_core!(asset, install_dir: dest) == dest end)

    assert output =~ "TRITON_PREBUILT_DIR=#{dest}"
    assert File.read!(Path.join(dest, "include/triton.h")) == "header"
    refute File.exists?(Path.join(dest, "bin/llvm-config"))
  end
end
