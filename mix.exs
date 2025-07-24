defmodule FSNotify.MixProject do
  use Mix.Project

  def project do
    [
      app: :fs_notify,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: Mix.compilers(),
      rustler_crates: [
        fs_notify: [
          path: "native/fs_notify",
          mode: :release
        ]
      ],
      description: description(),
      package: package(),
      docs: docs(),
      aliases: aliases(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:rustler, :mix]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:rustler, "~> 0.36.2"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38.2", only: :dev, runtime: false},
      {:styler, "~> 1.2", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    A cross-platform file system notification library for Elixir using Rust's notify library.
    Provides efficient file watching capabilities with configurable backends and event debouncing.
    """
  end

  defp package do
    [
      name: "fs_notify",
      files: ~w(lib native priv .formatter.exs mix.exs README* LICENSE* CHANGELOG*),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/jkwill87/fs_notify",
        "Docs" => "https://hexdocs.pm/fs_notify"
      },
      maintainers: ["Jessy Williams <jessy@jessywilliams.com>"]
    ]
  end

  defp docs do
    [
      main: "FSNotify",
      source_url: "https://github.com/jkwill87/fs_notify",
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        "Core API": [FSNotify, FSNotify.Watcher],
        Events: [FSNotify.Event],
        "Native Interface": [FSNotify.Native]
      ]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "compile"],
      format: ["format", "rust.format"],
      lint: ["format --check-formatted", "rust.format --check", "dialyzer", "rust.clippy"],
      "rust.format": &rust_format/1,
      "rust.clippy": &rust_clippy/1
    ]
  end

  defp rust_format(args) do
    Mix.shell().cmd("cargo fmt --manifest-path native/fs_notify/Cargo.toml #{Enum.join(args, " ")}")
  end

  defp rust_clippy(_args) do
    Mix.shell().cmd("cargo clippy --manifest-path native/fs_notify/Cargo.toml -- -D warnings")
  end
end
