defmodule Taskmaster.MixProject do
  use Mix.Project

  def project do
    [
      app: :taskmaster,
      version: "0.2.0",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: description(),

      # Docs
      name: "Taskmaster",
      source_url: "https://github.com/marcinwysocki/taskmaster",
      homepage_url: "https://hexdocs.pm/taskmaster",
      docs: [
        main: "Taskmaster",
        extras: ["README.md"],
        authors: ["Marcin Wysocki"]
      ],
      licenses: ["MIT"]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp description() do
    "A set of convenience functions for concurrent, asynchronous tasks, loosely inspired by JavaScript's Promises. Pure Elixir, no dependencies."
  end

  defp package() do
    [
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/marcinwysocki/taskmaster"},
      maintainers: ["Marcin Wysocki"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.22", only: :dev, runtime: false}
    ]
  end
end
