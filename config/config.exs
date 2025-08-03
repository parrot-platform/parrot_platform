import Config

config :parrot_platform,
  log_transactions: false,
  # This will be set by init/0
  allowed_methods: nil,
  # This will be set by init/0
  uas_options: nil

config :logger, :console,
  format: {Parrot.ParrotLogger, :format},
  metadata: [:file, :line, :function, :state, :call_id, :transaction_id, :dialog_id],
  inspect: [limit: 1000, printable_limit: 4096, pretty: false],
  level: :debug
