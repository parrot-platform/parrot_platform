defmodule Parrot.MixProject do
  use Mix.Project

  def project do
    [
      app: :parrot_platform,
      version: "0.0.1-alpha.3",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      releases: releases(),
      aliases: aliases(),

      # Hex.pm metadata
      name: "Parrot Platform",
      description:
        "Elixir libraries and OTP behaviours for building telecom applications with SIP protocol and media handling",
      package: package(),

      # Documentation
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets],
      mod: {Parrot.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nimble_parsec, "~> 1.3"},
      # Membrane Core and plugins
      {:membrane_core, "~> 1.0"},
      {:membrane_rtp_plugin, "~> 0.27"},
      {:membrane_rtp_format, "~> 0.10.0"},
      {:membrane_file_plugin, "~> 0.17"},
      {:membrane_udp_plugin, "~> 0.14"},
      {:membrane_g711_plugin, "~> 0.1"},
      {:membrane_rtp_g711_plugin, "~> 0.3.0"},
      {:ex_sdp, "~> 0.17.0"},
      {:membrane_wav_plugin, "~> 0.10"},
      {:membrane_mp3_mad_plugin, "~> 0.18"},
      {:membrane_ffmpeg_swresample_plugin, "~> 0.20"},
      {:membrane_realtimer_plugin, "~> 0.10.1"},
      {:membrane_portaudio_plugin, "~> 0.19.2"},

      # Documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp releases do
    [
      parrot: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent]
      ]
    ]
  end

  defp aliases do
    [
      test: ["test"],
      "test.sipp": &run_sipp_tests/1,
      docs: ["docs", &copy_images/1]
    ]
  end

  defp run_sipp_tests(_) do
    # Check if SIPP is installed
    case System.find_executable("sipp") do
      nil ->
        Mix.raise("SIPP is not installed. Please install it first.")

      _path ->
        Mix.Task.run("test", ["test/sipp/test_scenarios.exs"])
    end
  end

  defp copy_images(_) do
    # Ensure doc directory exists
    File.mkdir_p!("doc/assets")

    # Copy logo and any other assets from assets/ to doc/assets/
    case File.cp_r("assets", "doc/assets") do
      {:ok, _} ->
        Mix.shell().info("Copied assets to doc/assets")

      {:error, reason, file} ->
        Mix.shell().error("Failed to copy #{file}: #{inspect(reason)}")
    end
  end

  defp package do
    [
      licenses: ["GPL-2.0-or-later"],
      links: %{
        "GitHub" => "https://github.com/parrot-platform/parrot_platform"
      },
      maintainers: ["Brandon Youngdale"],
      files:
        ~w(lib priv .formatter.exs mix.exs README* LICENSE* CHANGELOG* guides assets usage-rules.md usage-rules),
      source_url: "https://github.com/parrot-platform/parrot_platform"
    ]
  end

  defp docs do
    [
      # The main page in the docs
      main: "overview",

      # Logo for the docs (optional)
      logo: "assets/logo.svg",

      # Assets to be copied to the docs
      assets: %{"assets" => "assets"},

      # Extra pages to include in the documentation
      extras: [
        "guides/overview.md": [title: "Overview"],
        "guides/architecture.md": [title: "Architecture"],
        "guides/sip-basics.md": [title: "SIP Basics"],
        "guides/media-handler.md": [title: "MediaHandler Guide"],
        "guides/state-machines.md": [title: "State Machines"],
        "guides/presentations.md": [title: "Presentations"]
      ],

      # Groups for modules in the sidebar
      groups_for_modules: [
        Core: [
          Parrot,
          Parrot.Application,
          Parrot.SipHandler,
          Parrot.MediaHandler
        ],
        "SIP Stack": [
          Parrot.Sip.Message,
          Parrot.Sip.Transaction,
          Parrot.Sip.Dialog,
          Parrot.Sip.Transport,
          Parrot.Sip.UAC,
          Parrot.Sip.UAS
        ],
        "SIP Headers": [
          ~r/^Parrot\.Sip\.Headers\./
        ],
        "Media Handling": [
          ~r/^Parrot\.Media\./
        ],
        Handlers: [
          ~r/^Parrot\.Sip\.Handlers\./,
          ~r/^Parrot\.Sip\.HandlerAdapter\./
        ]
      ],

      # Groups for extras (guides)
      groups_for_extras: [
        Introduction: ["guides/overview.md"],
        Guides: [
          "guides/architecture.md",
          "guides/sip-basics.md",
          "guides/media-handler.md",
          "guides/state-machines.md"
        ],
        Presentations: ["guides/presentations.md"]
      ],

      # Enable Mermaid diagram support
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  end

  defp before_closing_body_tag(:html) do
    """
    <script defer src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
    <script>
      document.addEventListener("DOMContentLoaded", function() {
        mermaid.initialize({
          startOnLoad: false,
        theme: 'neutral',
        themeVariables: {
          // Use neutral colors that work well on both light and dark backgrounds
          primaryColor: '#b3d9ff',
          primaryTextColor: '#000000',
          primaryBorderColor: '#0066cc',
          lineColor: '#0066cc',
          secondaryColor: '#ffcc99',
          secondaryTextColor: '#000000',
          secondaryBorderColor: '#ff6600',
          tertiaryColor: '#ffb3b3',
          tertiaryTextColor: '#000000',
          tertiaryBorderColor: '#cc0000',

          // Backgrounds - light colors for contrast
          background: '#f0f0f0',
          mainBkg: '#ffffff',
          secondBkg: '#f5f5f5',
          tertiaryBkg: '#eeeeee',

          // Notes - high contrast
          noteBkgColor: '#ffffcc',
          noteTextColor: '#000000',
          noteBorderColor: '#cccc00',

          // Sequence diagrams - ensure text is always dark and readable
          actorBorder: '#0066cc',
          actorBkg: '#e6f2ff',
          actorTextColor: '#000000',
          actorLineColor: '#0066cc',
          signalColor: '#000000',
          signalTextColor: '#000000',
          labelBoxBkgColor: '#e6f2ff',
          labelBoxBorderColor: '#0066cc',
          labelTextColor: '#000000',
          loopTextColor: '#000000',
          activationBorderColor: '#666666',
          activationBkgColor: '#f0f0f0',
          sequenceNumberColor: '#ffffff',

          // State diagrams
          stateBkg: '#e6f2ff',
          stateLabelColor: '#000000',

          // Flowcharts
          nodeTextColor: '#000000',
          nodeBkg: '#e6f2ff',
          nodeBorder: '#0066cc',
          clusterBkg: '#ffffcc',
          clusterBorder: '#cccc00',
          defaultLinkColor: '#000000',
          edgeLabelBackground: '#ffffff',

          // Font settings for better readability
          fontFamily: 'Arial, sans-serif',
          fontSize: '14px'
        }
        });

        function renderMermaidDiagrams() {
          let id = 0;
          for (const codeEl of document.querySelectorAll("pre code.mermaid, pre code.language-mermaid")) {
            const preEl = codeEl.parentElement;
            const graphDefinition = codeEl.textContent;
            const graphEl = document.createElement("div");
            const graphId = "mermaid-graph-" + id++;
            graphEl.classList.add("mermaid-diagram");

            mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
              graphEl.innerHTML = svg;
              bindFunctions?.(graphEl);
              preEl.insertAdjacentElement("afterend", graphEl);
              preEl.style.display = "none";
            }).catch(err => {
              console.error("Mermaid rendering error:", err);
              preEl.insertAdjacentHTML("afterend", "<p style='color: red;'>Error rendering diagram</p>");
            });
          }
        }

        // Initial render
        renderMermaidDiagrams();

        // Also listen for exdoc:loaded event for hexdocs.pm compatibility
        window.addEventListener("exdoc:loaded", renderMermaidDiagrams);
      });
    </script>
    <style>
      .mermaid-diagram {
        text-align: center;
        margin: 20px 0;
        padding: 20px;
        background-color: #ffffff;
        border: 1px solid #e0e0e0;
        border-radius: 8px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
      }
      .mermaid-diagram svg {
        max-width: 100%;
        height: auto;
      }
      /* Ensure text in diagrams is always black for readability */
      .mermaid-diagram text {
        fill: #000000 !important;
      }
      .mermaid-diagram .messageText {
        fill: #000000 !important;
        stroke: none !important;
      }
      .mermaid-diagram .noteText {
        fill: #000000 !important;
      }
      /* Make lines more visible */
      .mermaid-diagram line,
      .mermaid-diagram path {
        stroke-width: 2px;
      }
      /* Dark mode adjustments */
      @media (prefers-color-scheme: dark) {
        .mermaid-diagram {
          background-color: #ffffff;
          border-color: #cccccc;
        }
      }
    </style>
    """
  end

  defp before_closing_body_tag(_), do: ""
end
