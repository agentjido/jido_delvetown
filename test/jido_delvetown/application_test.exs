defmodule JidoDelvetown.ApplicationTest do
  use ExUnit.Case, async: true

  @source_root Path.expand("../../lib/jido_delvetown", __DIR__)
  @facade Path.expand("../../lib/jido_delvetown.ex", __DIR__)
  @root_files ~w(agent.ex application.ex config.ex)
  @subsystems ~w(actions participation persistence protocol publishing runtime social workers)

  test "the source root contains only the application, agent, and config" do
    assert root_files(@source_root) == @root_files
    assert File.regular?(@facade)
  end

  test "the test tree mirrors every source subsystem" do
    assert child_directories(@source_root) == @subsystems
    assert child_directories(__DIR__) == @subsystems
  end

  defp root_files(path) do
    path
    |> Path.join("*.ex")
    |> Path.wildcard()
    |> Enum.map(&Path.basename/1)
    |> Enum.sort()
  end

  defp child_directories(path) do
    path
    |> File.ls!()
    |> Enum.filter(&File.dir?(Path.join(path, &1)))
    |> Enum.sort()
  end
end
