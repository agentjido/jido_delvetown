defmodule JidoDelvetown.Settings.SecretStoreTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias JidoDelvetown.Settings.SecretStore

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "jido-delvetown-key-test-#{System.unique_integer([:positive, :monotonic])}"
      )

    path = Path.join(directory, "settings.key")
    other_path = Path.join(directory, "other.key")

    on_exit(fn ->
      File.rm(path)
      File.rm(other_path)
      File.rmdir(directory)
    end)

    %{directory: directory, path: path, other_path: other_path}
  end

  test "creates one owner-only key and keeps it stable", %{path: path} do
    refute File.exists?(path)

    assert {:ok, %{path: ^path}} = SecretStore.ensure_key(path: path)
    assert {:ok, first_key} = File.read(path)
    assert byte_size(first_key) == 32

    assert {:ok, %{mode: mode, size: 32, type: :regular}} = File.stat(path)
    assert (mode &&& 0o077) == 0

    File.chmod!(path, 0o644)
    assert {:ok, %{path: ^path}} = SecretStore.ensure_key(path: path)
    assert {:ok, ^first_key} = File.read(path)
    assert {:ok, %{mode: repaired_mode}} = File.stat(path)
    assert (repaired_mode &&& 0o077) == 0
  end

  test "encrypts with a fresh nonce and authenticates the setting name", %{
    path: path,
    other_path: other_path
  } do
    plaintext = "secret-value"

    assert {:ok, first} = SecretStore.encrypt(:account_app_password, plaintext, path: path)
    assert {:ok, second} = SecretStore.encrypt(:account_app_password, plaintext, path: path)

    assert first != second
    refute first =~ plaintext
    assert SecretStore.encrypted?(first)

    assert {:ok, ^plaintext} =
             SecretStore.decrypt(:account_app_password, first, path: path)

    assert {:error, :secret_decryption_failed} =
             SecretStore.decrypt(:another_setting, first, path: path)

    assert {:ok, _key} = SecretStore.ensure_key(path: other_path)

    assert {:error, :secret_decryption_failed} =
             SecretStore.decrypt(:account_app_password, first, path: other_path)

    prefix_size = byte_size(first) - 1
    <<prefix::binary-size(^prefix_size), last>> = first
    tampered = prefix <> <<Bitwise.bxor(last, 1)>>

    assert {:error, :secret_decryption_failed} =
             SecretStore.decrypt(:account_app_password, tampered, path: path)
  end

  test "refuses an existing invalid key file", %{directory: directory, path: path} do
    File.mkdir_p!(directory)
    File.write!(path, "too-short")

    assert {:error, :invalid_settings_key} = SecretStore.ensure_key(path: path)
    assert {:ok, "too-short"} = File.read(path)
  end
end
