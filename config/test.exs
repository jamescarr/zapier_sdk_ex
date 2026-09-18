import Config

# Route every request into Req's test adapter so the suite never touches the
# network. Individual tests install their own stub with `Req.Test.stub/2`.
config :zapier_sdk,
  req_options: [plug: {Req.Test, ZapierSDK}],
  token: "test-token",
  # Retries only add latency to a suite that already controls every response.
  max_retries: 0,
  connections: [
    drive: {"google-drive", "conn-drive-uuid"},
    slack: {"slack", "conn-slack-uuid"}
  ]
