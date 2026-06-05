-module(rally_runtime_session_ffi).
-export([encrypt/3, decrypt/3]).

encrypt(Key, Plaintext, AAD) ->
    try
        IV = crypto:strong_rand_bytes(12),
        {Ciphertext, CipherTag} = crypto:crypto_one_time_aead(
            aes_256_gcm, Key, IV, Plaintext, AAD, true
        ),
        {ok, {encrypted, IV, Ciphertext, CipherTag}}
    catch
        _:_ -> {error, nil}
    end.

decrypt(Key, {encrypted, IV, Ciphertext, Tag}, AAD) ->
    try
        case crypto:crypto_one_time_aead(
            aes_256_gcm, Key, IV, Ciphertext, AAD, Tag, false
        ) of
            Plaintext when is_binary(Plaintext) -> {ok, Plaintext};
            error -> {error, nil}
        end
    catch
        _:_ -> {error, nil}
    end.
