# Contributing

Issues and pull requests are welcome. Describe the problem and expected behavior; keep changes focused. Include macOS/toolchain version, output model, connection type, and reproduction steps for audio bugs. Remove device identifiers, paths, recordings, and credentials before sharing diagnostics.

Run `Tests/run_tests.sh`, `python3 Tests/check_callbacks.py`, and `python3 Tests/check_lifecycle.py`, then `bash build.sh` on macOS. Native off-state checks are documented in Tests/README.md. Do not claim live acceptance from fixtures alone.

Contributions are made under the project’s MIT license. Include provenance and compatible license notices for any new dependency or asset. The current runtime uses only Apple frameworks and in-tree code.
