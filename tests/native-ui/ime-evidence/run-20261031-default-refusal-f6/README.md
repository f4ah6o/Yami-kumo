# Default Settings entry refusal, before the selector change

Local nested Xvfb/Weston x11 + IBus/Mozc, with no input injected. App source
`f6c4b40abbecd74b76a1fb459c360a104fd132dd`, GPUI source
`b28cff9a8a92a155e67421a397a1030dedac9301`, binary SHA-256
`b1b1b02ea557ba8535e5d7e70919682530895a0d5c973aef58424dfa6b197a0f`.
The ad-hoc `drive.py`/`session.sh` content was saved in the enclosing evidence
commit; this is separate from the app source revision. `ubuntu.exe
--settings-e2e` exited -6 and logged `ordered input requires a retained owner`.
This is an expected reproduction of a failure, not a successful GUI or live
IME test.

CI for app source f6c4b40 [failed the Ubuntu Settings job](https://github.com/f4ah6o/Yami-kumo/actions/runs/41149285901/job/124381674938)
with the same exit code, but its child stderr was unavailable from the job log;
the local reproduction does not prove the actual CI child error text.

SHA-256:

```
6835e912a9799450b89e2926d17758e7a719bce5953b808ca0152fdca0148c91  app.log
2ca59a93ce44cef64dae21ea8dfa7bfc0660a27cfdae05d5dacf100159a7ce7b  drive.py
c19e0f19a0f6140e925b88e8cb53a3d5cb2b5722cfb054b49e63d9af3eca6dea  result.json
387d50d87c57c04197c85df5d9ec7b4b2c00efb3409db7b215bc0189ba316aa6  session.log
e4f0a814b400489138b2e1f18de29fb5a225c8e009351aa49af7a21febad8c08  session.sh
```
