defmodule ParrotExampleUac.MixProject do
  use Mix.Project

  def project do
    [
      app: :parrot_example_uac,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      # Use local parrot_platform when available
      {:parrot_platform, path: "../..", override: true}
      # Or use from hex when published:
      # {:parrot_platform, "~> 0.0.1-alpha"}
    ]
  end
end