defmodule JidoDelvetown.Settings.SecretStore do
  @moduledoc """
  Encrypts secret settings with local key material.

  The key file is created next to the SQLite database with owner-only access.
  Stored envelopes use AES-256-GCM and a new nonce for each write.
  """

  import Bitwise

  alias JidoDelvetown.Config

  @key_bytes 32
  @nonce_bytes 12
  @tag_bytes 16
  @prefix "enc:v1:"
  @owner_only 0o600

  @spec ensure_key(keyword()) :: {:ok, %{path: String.t()}} | {:error, term()}
  def ensure_key(opts \\ []) do
    path = Keyword.get(opts, :path, Config.settings_key_path())

    with :ok <- validate_path(path),
         :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, _key} <- load_or_create_key(path) do
      {:ok, %{path: path}}
    end
  end

  @spec encrypt(atom() | String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def encrypt(setting, plaintext, opts \\ [])

  def encrypt(setting, plaintext, opts) when is_binary(plaintext) do
    with {:ok, key} <- key(opts) do
      nonce = :crypto.strong_rand_bytes(@nonce_bytes)

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(
          :aes_256_gcm,
          key,
          nonce,
          plaintext,
          associated_data(setting),
          @tag_bytes,
          true
        )

      envelope = Base.url_encode64(nonce <> tag <> ciphertext, padding: false)
      {:ok, @prefix <> envelope}
    end
  rescue
    _error -> {:error, :secret_encryption_failed}
  end

  def encrypt(_setting, _plaintext, _opts), do: {:error, :invalid_secret_value}

  @spec decrypt(atom() | String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def decrypt(setting, envelope, opts \\ [])

  def decrypt(setting, @prefix <> encoded, opts) do
    with {:ok, payload} <- Base.url_decode64(encoded, padding: false),
         <<nonce::binary-size(@nonce_bytes), tag::binary-size(@tag_bytes), ciphertext::binary>> <-
           payload,
         {:ok, key} <- key(opts),
         plaintext when is_binary(plaintext) <-
           :crypto.crypto_one_time_aead(
             :aes_256_gcm,
             key,
             nonce,
             ciphertext,
             associated_data(setting),
             tag,
             false
           ) do
      {:ok, plaintext}
    else
      _error -> {:error, :secret_decryption_failed}
    end
  rescue
    _error -> {:error, :secret_decryption_failed}
  end

  def decrypt(_setting, _envelope, _opts), do: {:error, :invalid_secret_envelope}

  @spec encrypted?(term()) :: boolean()
  def encrypted?(@prefix <> _encoded), do: true
  def encrypted?(_value), do: false

  defp key(opts) do
    path = Keyword.get(opts, :path, Config.settings_key_path())

    with {:ok, _info} <- ensure_key(path: path) do
      read_key(path)
    end
  end

  defp load_or_create_key(path) do
    case read_key(path) do
      {:ok, key} -> {:ok, key}
      {:error, :enoent} -> create_key(path)
      {:error, _reason} = error -> error
    end
  end

  defp create_key(path) do
    key = :crypto.strong_rand_bytes(@key_bytes)
    suffix = :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
    temporary_path = path <> ".tmp-" <> suffix

    try do
      with :ok <- File.write(temporary_path, key, [:binary, :exclusive]),
           :ok <- File.chmod(temporary_path, @owner_only) do
        case File.ln(temporary_path, path) do
          :ok -> read_key(path)
          {:error, :eexist} -> read_key(path)
          {:error, reason} -> {:error, {:settings_key_create_failed, reason}}
        end
      else
        {:error, reason} -> {:error, {:settings_key_create_failed, reason}}
      end
    after
      File.rm(temporary_path)
    end
  end

  defp read_key(path) do
    case File.lstat(path) do
      {:ok, %{type: :regular, size: @key_bytes}} ->
        with :ok <- File.chmod(path, @owner_only),
             {:ok, %{mode: mode}} <- File.stat(path),
             true <- (mode &&& 0o077) == 0,
             {:ok, <<key::binary-size(@key_bytes)>>} <- File.read(path) do
          {:ok, key}
        else
          false -> {:error, :insecure_settings_key_permissions}
          {:ok, _invalid} -> {:error, :invalid_settings_key}
          {:error, reason} -> {:error, {:settings_key_read_failed, reason}}
        end

      {:ok, _invalid} ->
        {:error, :invalid_settings_key}

      {:error, :enoent} ->
        {:error, :enoent}

      {:error, reason} ->
        {:error, {:settings_key_read_failed, reason}}
    end
  end

  defp validate_path(path) when is_binary(path) do
    if String.valid?(path) and path != "",
      do: :ok,
      else: {:error, :invalid_settings_key_path}
  end

  defp validate_path(_path), do: {:error, :invalid_settings_key_path}

  defp associated_data(setting),
    do: "jido-delvetown:settings:#{setting}:v1"
end
