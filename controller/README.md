# EasyNet Controller scaffold

This is a development-only Go version stub. It performs no deployment,
SSH, VPN, vault, configuration, or network operations.

The module uses only the Go standard library. Build it from the repository
root with the pinned Go 1.27.2 toolchain:

```sh
go -C controller build -o /private/tmp/easynet-controller-scaffold ./cmd/easynet-controller
```

The only supported command is `easynet-controller --version`. Other arguments
print the fixed usage line and return status 2. No default operational action
is available.

This scaffold does not satisfy product acceptance. Later stages must pass their
reviewed implementation and acceptance gates before operational capabilities
are considered.
