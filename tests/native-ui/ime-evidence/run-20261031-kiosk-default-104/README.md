# Retained Settings startup under a kiosk compositor

Local diagnostic only: framework source
`b28cff9a8a92a155e67421a397a1030dedac9301`, Yami/app source
`0ee49e9c593e14f2336c1ff8a7e8154a3b0b2e10`, separately built native binary
SHA-256 `e85aa8ac5e9f4bed35f3fd63f9f2a3782676911b97a2e404d3f678b98ecd830f`.
Harness `drive.py` and `session.sh` are saved verbatim in the enclosing
checkpoint commit; they are not the app source revision. No package lock was
used: both CI source pins select the framework SHA above. Local build log
`/workspace/scratch/yami-default-exact-build.log` SHA-256
`623de946d5907a056d2779e3e9c003db15ae615681927611c38d05562fcfa187`.

Linux 6.18.57 x86_64, Moon `0.1.20261012 (748b63c)`, local locked Weston
x11 + gl renderer + kiosk shell `--no-config`, Xvfb. No keyboard/IME input or
X focus was injected. Running `ubuntu.exe --settings-e2e` produced no Settings
frame marker and entered the control loop with
`retained_begin: unsupported_capability`. A status request reported a suspended
owner and retained host. The exploratory fixture then sent SIGTERM: this loses
the in-memory owner, so cleanup is explicitly FAIL and live IME is NOT_RUN.

The [#104 CI job](https://github.com/f4ah6o/Yami-kumo/actions/runs/41149925032/job/124383761387)
reported `timed out waiting for Settings output; markers=[]`. Its child stderr
was unavailable, so this local CI-like profile isolates a plausible cause and
does not prove the exact CI-internal error. A separate local desktop-shell
profile on the same app did advertise text-input-v1 and produced frames; the
profiles must not be conflated. Retained-route claim currently prohibits direct
keyboard mode, so safe no-IME fallback still needs a host contract and tests.

File SHA-256:

```
223ca19e53f0444cc4b9223e5dd096e9f8cfc8ef70ac52c32bd534aad88080aa  app.log
4bf4a13a327f67be723ba78b46acaa8e156914d8e839260a07026c037384502d  drive.py
eac0bf26820e8bbfa4ae14cf3694bcf95877557676bf2d5f62d8710090cc0f72  result.json
9724e856c5cf06e1e221be1ee849840f036fe6ffa33a4204a62629fe3361e8ed  session.log
4ba6e0aca484417b3b2ae3f0bdee0ea776487e04137167013ffd187f422f6af3  session.sh
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  weston-stdio.log
aeb54c0d780314d43c5c4374d51a1950cfc99f6d5acf8f78b3d1ad8fdb256e61  weston.log.gz
cf96eac327aa72a59b83b10e26ccaf93dbb766cf75be3dcf746a4dd9c92f59c5  weston.log (decompressed bytes)
```
