defmodule ParrotNew.MixProject do
  use Mix.Project

  def project do
    [
      app: :parrot_new,
      version: "0.0.1-alpha.1",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Parrot Platform project generators",
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :eex]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    # No dependencies - this is just a generator
    []
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/byoungdale/parrot"
      },
      maintainers: ["Brandon Youngdale"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*),
      source_url: "https://github.com/byoungdale/parrot"
    ]
  end
end
