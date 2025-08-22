defmodule Parrot.SippTest do
  use ExUnit.Case
  
  @moduletag :sipp
  
  require Logger

  # Simple handler for SIPp integration tests
  defmodule SippTestHandler do
    use Parrot.UasHandler

    def handle_invite(_request, _state) do
      # Accept all INVITEs with a simple SDP
      sdp = """
      v=0
      o=- 0 0 IN IP4 127.0.0.1
      s=-
      c=IN IP4 127.0.0.1
      t=0 0
      m=audio 4000 RTP/AVP 8 111
      a=rtpmap:8 PCMA/8000
      a=rtpmap:111 OPUS/48000
      """

      {:respond, 200, "OK", %{}, sdp}
    end

    def handle_ack(_request, _state) do
      :noreply
    end

    def handle_bye(_request, _state) do
      {:respond, 200, "OK", %{}, ""}
    end

    def handle_cancel(_request, _state) do
      {:respond, 200, "OK", %{}, ""}
    end

    def handle_options(_request, _state) do
      {:respond, 200, "OK", %{}, ""}
    end
  end

  @scenarios_path Path.expand("scenarios/basic", __DIR__)
  @logs_path Path.expand("logs", __DIR__)
  @sipp_port 5080

  setup_all do
    System.cmd("pkill", ["-9", "sipp"], stderr_to_stdout: true)

    # Explicitly ensure Parrot application is started for this test process
    case Application.ensure_all_started(:parrot_platform) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, reason} -> raise "Could not start :parrot_platform application: #{inspect(reason)}"
    end

    # Ensure logs directory exists
    File.mkdir_p!(@logs_path)

    # Use the test handler for SIPp tests
    handler_module = Parrot.SippTest.SippTestHandler
    handler_state = %{}

    # Get test configuration
    test_log_level = Application.get_env(:parrot_platform, :test_log_level, :warning)
    test_sip_trace = Application.get_env(:parrot_platform, :test_sip_trace, false)

    # Create handler with test configuration
    sip_handler =
      Parrot.Sip.Handler.new(
        Parrot.Sip.HandlerAdapter.Core,
        {handler_module, handler_state},
        log_level: test_log_level,
        sip_trace: test_sip_trace
      )

    opts = %{
      listen_port: 5060,
      handler: sip_handler
    }

    Logger.info("Starting UDP transport...")
    :ok = Parrot.Sip.Transport.StateMachine.start_udp(opts)

    on_exit(fn ->
      Logger.info("Stopping UDP transport...")
      Parrot.Sip.Transport.StateMachine.stop_udp()
    end)

    :ok
  end

  describe "Basic UAC Scenarios" do
    # @tag :sipp
    # @tag order: 1
    # test "1. OPTIONS ping" do
    #   scenario_name = "uac_options"
    #   status = run_sipp(@scenarios_path, scenario_name)
    #   assert status == 0
    # end

    @tag :sipp
    @tag order: 2
    test "2. INVITE call flow" do
      scenario_name = "uac_invite"
      status = run_sipp(@scenarios_path, scenario_name)
      assert status == 0
    end

    @tag :sipp
    @tag order: 3
    test "3. INVITE call flow with longer duration" do
      scenario_name = "uac_invite_long"
      status = run_sipp(@scenarios_path, scenario_name)
      assert status == 0
    end

    @tag :sipp
    @tag order: 4
    test "4. INVITE with PCMA codec (G.711 A-law)" do
      scenario_name = "uac_invite_pcma"
      status = run_sipp(@scenarios_path, scenario_name)
      assert status == 0
    end
  end

  def run_sipp(_sipp_path, scenario_name) do
    scenario_file = Path.join(@scenarios_path, "#{scenario_name}.xml")
    Logger.info("Running scenario: #{scenario_file}")

    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d_%H%M%S")

    case System.find_executable("sipp") do
      nil ->
        flunk("SIPp is not installed")

      sipp_path ->
        Logger.info("Found SIPp at: #{sipp_path}")

        args = [
          "-sf",
          scenario_file,
          "-m",
          "1",
          "-l",
          "1",
          "-timeout",
          "20",
          "-timeout_error",
          "-trace_err",
          "-trace_msg",
          "-trace_logs",
          "-p",
          "#{@sipp_port}",
          "-error_file",
          Path.join(@logs_path, "#{scenario_name}_#{timestamp}_errors.log"),
          "-message_file",
          Path.join(@logs_path, "#{scenario_name}_#{timestamp}_messages.log"),
          "-log_file",
          Path.join(@logs_path, "#{scenario_name}_#{timestamp}.log"),
          "127.0.0.1:5060"
        ]

        Logger.info("Executing: sipp #{Enum.join(args, " ")}")

        {output, status} = System.cmd(sipp_path, args, stderr_to_stdout: true)

        Logger.info("SIPp Output:\n#{output}")
        Logger.info("SIPp Status: #{status}")

        status
    end
  end
end
