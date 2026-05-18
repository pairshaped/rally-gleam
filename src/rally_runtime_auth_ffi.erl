-module(rally_runtime_auth_ffi).
-export([pbkdf2_hmac_sha256/4]).

pbkdf2_hmac_sha256(Secret, Salt, Iterations, Length) ->
    crypto:pbkdf2_hmac(sha256, Secret, Salt, Iterations, Length).
